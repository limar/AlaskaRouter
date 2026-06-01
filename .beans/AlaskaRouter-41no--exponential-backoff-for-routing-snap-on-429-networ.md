---
# AlaskaRouter-41no
title: Exponential backoff for routing snap on 429 / network errors
status: completed
type: task
priority: high
created_at: 2026-06-01T09:12:57Z
updated_at: 2026-06-01T09:31:18Z
---

## Problem

`RootView.runSnap` ([App/RootView.swift:432](AlaskaRouter/App/RootView.swift:432)) catches every routing failure and immediately falls through to `pendingSnapKey`. If the user keeps editing the trip during throttling or a flaky network, each waypoint change re-fires `scheduleSnapForCurrentTrip` after a 500 ms debounce — burning fresh calls into the same throttled server, all guaranteed to fail again.

Public OSRM is "polite use" with no documented hard limit; ORS (v2+) has a strict daily quota. Either way, hammering a backend that just told us "no" wastes calls and slows recovery.

## Fix

In `OSRMProvider.snap` (or in `runSnap`), on `RoutingError.http(statusCode: 429)` or transport errors, schedule the next retry with exponential backoff. Skip the retry if the geometry key has changed in the meantime (user moved on).

Backoff schedule: 2 s → 5 s → 15 s → 45 s → 120 s, capped. Resets on any successful call.

While the backoff window is open:
- New geometry changes still try once (the user may have edited around the bad pair).
- If that also fails with 429, extend the window.
- The `pendingSnap` dashed line stays visible; user feedback unchanged.

State lives on the RoutingProvider (or a small RoutingRetryPolicy struct on RootView), not in SwiftData — backoff state is process-local.

## Acceptance

- Five consecutive failed snaps within 10 s do NOT result in five immediate retries.
- A successful snap (manual reconnect, or 429 window closes) resets the backoff to 0.
- Tests: mock RoutingProvider that returns 429 N times then Ok; assert call timestamps respect the schedule.

## TODOs

- [x] `Routing/RoutingRetryPolicy.swift` — small struct holding `nextAllowedAt: Date`, `consecutiveFailures: Int`, helper `recordFailure()` / `recordSuccess()` / `canFireNow() -> Bool`.
- [x] Wired into `RootView.runSnap` (the actual fetch step). On a blocked window: mark pendingSnap, `Task.sleep` until `nextAllowedAt`, re-check geometry, then fire.
- [x] Distinguished via a `FailureKind` enum: `.rateLimited` advances the schedule; `.transport` leaves the schedule alone and yields to NetworkMonitor.onReconnect. `RoutingError.server` (NoRoute / NoMatch) skips backoff entirely — not a throttle.
- [x] `RoutingRetryPolicyTests` — 7 tests covering fresh state, single 429, walking the schedule, holding at the maximum, success reset, transport non-effect, and clock-driven window reopen. Uses an injectable now-clock so tests don't sleep.

## Summary of Changes

**New:** Routing/RoutingRetryPolicy.swift — @MainActor class holding consecutiveRateLimitFailures + nextAllowedAt. Public schedule [2, 5, 15, 45, 120] seconds, indexed by consecutive rate-limit failures, held at the last value on overflow. Records FailureKind.rateLimited vs FailureKind.transport differently: only the former advances the schedule.

**Wired in RootView.runSnap:**
- Before firing, if !retryPolicy.canFireNow: set pendingSnapKey, Task.sleep(secondsUntilNextAllowed), recheck Task.isCancelled + tripGeometryKey, then fire.
- On success: retryPolicy.recordSuccess() resets the counter.
- On RoutingError.http (429 / 5xx): recordFailure(.rateLimited).
- On RoutingError.server (NoRoute / NoMatch): no backoff — not a throttle, just bail to pendingSnap.
- On any other catch (transport, decoding): recordFailure(.transport) — keeps schedule untouched; NetworkMonitor.onReconnect handles the retry.

**Effect:** five rapid 429s within 10 s now occupy retries 2 + 5 + 15 + 45 + 120 s out (total ~3 min) instead of five immediate same-second hits. One success anywhere clears the backoff.

**Tests:** 7 new in RoutingRetryPolicyTests using an injectable clock. Total 64/64 pass.
