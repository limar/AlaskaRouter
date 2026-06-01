// Constants and guard helpers for outgoing routing-provider requests
// (AlaskaRouter-2l0i).
//
// Every outbound `RoutingProvider.snap(waypoints:)` call is bounded by
// `maxLocationsPerRoutingRequest`. The partial-fetch orchestration in
// RootView splits work into runs and chunks each run so this cap is
// respected by construction.
//
// Why the cap exists:
//
//   1. Backend hard limits — the public FOSSGIS Valhalla server (which
//      we're adopting for ferry support via [AlaskaRouter-y3g3]) rejects
//      any /route request with more than 20 locations: HTTP 400
//      `Exceeded max locations: 20`. We stay well under that cap so a
//      future tightening doesn't break us.
//   2. Failure granularity — a chunk that fails marks only its pairs as
//      pendingSnap (dashed). Smaller chunks = smaller dashed regions on
//      a partial failure. Set to 10 ⇒ at most 9 dashed legs per failure.
//   3. Polite per-request payload size — Alaska LTE is slow; small
//      requests round-trip faster and degrade more gracefully under
//      flaky connectivity.
//
// `assertChunked(_:)` fires only in debug builds (`assert`, not
// `precondition` — production must NOT crash on this per the project's
// no-crashes rule). The release-build guarantee comes from the chunking
// being correct by construction; the assertion is a tripwire for
// regressions where someone bypasses the planner.

import Foundation
import CoreLocation

enum RoutingRequestLimits {
    /// Max waypoints permitted in any single outbound routing request.
    /// See file header for rationale.
    static let maxLocationsPerRoutingRequest: Int = 10

    /// Debug-only tripwire. Fires (in debug builds) if any code path
    /// hands the routing provider more waypoints than the cap allows.
    /// Production builds do not crash — release behavior is "send the
    /// oversized request and let the backend reject it" rather than
    /// fatal-error (per the no-crashes rule). If you see this in your
    /// debugger, the partial-fetch planner has a regression: somebody
    /// is calling `RoutingProvider.snap` without going through the
    /// chunker. Find that call site, run it through `SegmentPlanner`.
    static func assertChunked(_ waypointCount: Int,
                              file: StaticString = #file,
                              line: UInt = #line) {
        assert(
            waypointCount <= maxLocationsPerRoutingRequest,
            "Routing request has \(waypointCount) waypoints, exceeds " +
            "RoutingRequestLimits.maxLocationsPerRoutingRequest (\(maxLocationsPerRoutingRequest)). " +
            "Partial-fetch planner regression — route this call through SegmentPlanner.",
            file: file, line: line
        )
    }
}
