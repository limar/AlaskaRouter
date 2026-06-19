// Adaptive bisection recovery for poisoned routing runs (AlaskaRouter-d0wt).
//
// WHY this exists
// ---------------
// The partial-fetch planner (SegmentPlanner) batches every *contiguous*
// run of un-cached pairs into a SINGLE provider request: waypoints
// A,B,C,…,N ask Valhalla for legs A→B, B→C, … in one round-trip. That's
// the right call for the happy path — one request instead of N, which
// matters on the rate-limited FOSSGIS demo (1 req/s) and on slow Alaska
// LTE.
//
// But a Valhalla /route request is ALL-OR-NOTHING: if any single leg has
// no drivable path, the whole request fails (HTTP 400 / error_code 442)
// and tells us nothing about the *other* legs. So one unroutable stop in
// the middle of a run "poisons" every routable leg around it — they all
// get dashed even though, fetched alone, they'd snap fine.
//
// Real report (the Alaska trip): stop 12 is the geographic centre of
// Denali Park, miles from any road, so it's genuinely unroutable. Yet
// stops 13→20 — all sitting on the highway — stayed dashed too, because
// they shared one batched request with the Denali stop. Building a fresh
// trip without that stop routed everything fine, which is the tell.
//
// HOW recovery works
// ------------------
// On a *confirmed* no-route for a run with >1 pair, bisect the run into
// two halves that SHARE their boundary waypoint (so pair coverage stays
// exact and contiguous) and re-issue each half. A half that routes is
// salvaged in one request; a half that still fails is bisected again.
// Recursion bottoms out at a single pair: a single-pair run that returns
// no-route is the genuinely unroutable leg and stays pending (dashed).
// Net result: only the legs that actually touch an unroutable stop stay
// dashed; every routable leg around them snaps.
//
// Cost: O(k · log n) extra requests, where k = number of unroutable stops
// in the run (usually 1) and n = pairs in the run. For the Denali run
// (9 pairs, 1 bad stop) that's ~7 small requests instead of the 1 that
// failed — but ONLY on the rare failure path. The happy path is untouched.
//
// SIMPLER ALTERNATIVE (deliberately not chosen)
// ---------------------------------------------
// We could skip bisection and just re-issue every pair of the failed run
// as its own single-pair request — N requests, one per leg. That's less
// code and trivially correct. We chose bisection because a run can be the
// full chunk cap (10 waypoints = 9 pairs) and the FOSSGIS limiter is
// 1 req/s, so halving the request count on the (already slow) failure
// path is worth the modest extra complexity. If this ever feels too
// clever, the per-pair fallback is a safe drop-in: replace the `split`
// recursion in `recover` with a flat map over consecutive pairs, each
// snapped individually.

import Foundation
import CoreLocation

enum SegmentRecovery {

    /// What a single (sub-)run snap attempt told us. The caller injects the
    /// actual snap (a `RoutingProvider` call in production, a stub in
    /// tests), so this stays pure and unit-testable — no network, no
    /// provider, no MainActor.
    enum SnapOutcome: Sendable {
        /// Routed cleanly. Carries the geometry/legs to write to cache.
        case ok(RoutingResult)
        /// At least one leg has no drivable path. Permanent until the
        /// geometry changes — this is what drives the bisection.
        case noRoute
        /// Rate-limit or network blip — NOT a geometry problem. Don't blame
        /// the run; leave it pending for the next snap cycle.
        case transient
    }

    /// The resolved fate of a leaf (sub-)run after recovery.
    enum Resolved: Sendable {
        /// A sub-run that routed cleanly; covers ≥ 1 pair. Write to cache.
        case snapped(MissingRun, RoutingResult)
        /// A single-pair run with no path — the genuinely unroutable leg.
        /// Stays pending (dashed); only editing the stop fixes it.
        case unroutable(MissingRun)
        /// A sub-run we couldn't resolve because of a transient error.
        /// Leave it pending for the next snap cycle; do NOT mark it
        /// unroutable (the geometry might be perfectly fine).
        case pending(MissingRun)
    }

    /// Split a run with ≥ 2 pairs into two halves that share their boundary
    /// waypoint, so the two halves' pair coverage exactly equals the
    /// parent's (no gap, no overlap). Returns `nil` for a 0- or 1-pair run
    /// (nothing left to bisect). Pure — unit-tested independently of the
    /// async driver.
    static func split(_ run: MissingRun) -> (MissingRun, MissingRun)? {
        let pairs = run.pairCount
        guard pairs >= 2 else { return nil }
        // `mid` is a count of pairs in the left half: 1...pairs-1. The
        // shared boundary waypoint is run.waypoints[mid] — it's the LAST
        // waypoint of the left half and the FIRST of the right half.
        let mid = pairs / 2
        let left = MissingRun(
            firstPairIndex: run.firstPairIndex,
            waypoints: Array(run.waypoints[0 ... mid])
        )
        let right = MissingRun(
            firstPairIndex: run.firstPairIndex + mid,
            waypoints: Array(run.waypoints[mid...])
        )
        return (left, right)
    }

    /// Adaptively bisect `run`, calling `snap` for each (sub-)run, until
    /// every routable leg is salvaged and every unroutable leg is isolated
    /// to a single pair. `snap` mirrors `RoutingProvider.snap` but is a
    /// closure so tests can drive it deterministically without a network.
    ///
    /// Note: the first call re-snaps the full `run` even though the caller
    /// only invokes `recover` after the run already failed once. That's one
    /// redundant (cheap, fast-failing) request, traded for a uniform,
    /// self-contained recursion that's trivial to unit-test from scratch.
    static func recover(
        _ run: MissingRun,
        snap: @Sendable (MissingRun) async -> SnapOutcome
    ) async -> [Resolved] {
        switch await snap(run) {
        case let .ok(result):
            return [.snapped(run, result)]
        case .transient:
            // Backend hiccup, not a geometry problem. Leave the whole
            // sub-run pending; the outer retry loop tries again later.
            return [.pending(run)]
        case .noRoute:
            guard let (left, right) = split(run) else {
                // A single pair with no path: the real culprit.
                return [.unroutable(run)]
            }
            // Sequential, not concurrent. The FOSSGIS limiter is 1 req/s
            // and recovery is already the slow path; firing both halves at
            // once would just trip the limiter and turn clean no-route
            // signals into transient failures.
            let l = await recover(left, snap: snap)
            let r = await recover(right, snap: snap)
            return l + r
        }
    }
}
