// Exponential backoff for the routing snap pipeline (AlaskaRouter-41no).
//
// On a 429 (rate limit) or http error from the routing provider, hammering
// the same backend immediately produces another 429 and burns calls during
// the moment we should be slowing down. This policy holds the next
// permitted call time and a consecutive-failure counter; the snap pipeline
// consults `canFireNow` before issuing a request.
//
// Transport-level offlines (no network at all) are NOT counted as
// rate-limit failures — that's a separate signal handled by NetworkMonitor
// and the existing `pendingSnapKey` retry-on-reconnect path. Use
// `recordFailure(kind: .http429)` only when the server replied with a
// throttle / 5xx; use `recordFailure(kind: .transport)` for transport
// errors so we can gate the schedule differently if we want to later.
//
// State is process-local — no SwiftData. A successful call resets.

import Foundation

@MainActor
final class RoutingRetryPolicy {
    enum FailureKind: Sendable {
        /// Server reachable but throttling / 5xx — exponential backoff applies.
        case rateLimited
        /// Transport failure (no network). Cleared on next attempt — the
        /// pending-on-reconnect flow handles the retry. No exponential delay.
        case transport
    }

    /// Backoff schedule (seconds) indexed by consecutive rate-limit failures.
    /// After exhausting the schedule we hold at the last value (120 s).
    static let schedule: [TimeInterval] = [2, 5, 15, 45, 120]

    private(set) var consecutiveRateLimitFailures = 0
    private(set) var nextAllowedAt: Date = .distantPast
    private let now: @MainActor () -> Date

    init(now: @escaping @MainActor () -> Date = { .now }) {
        self.now = now
    }

    var canFireNow: Bool { now() >= nextAllowedAt }

    var secondsUntilNextAllowed: TimeInterval {
        max(0, nextAllowedAt.timeIntervalSince(now()))
    }

    func recordFailure(kind: FailureKind) {
        switch kind {
        case .rateLimited:
            consecutiveRateLimitFailures += 1
            let idx = min(consecutiveRateLimitFailures - 1, Self.schedule.count - 1)
            nextAllowedAt = now().addingTimeInterval(Self.schedule[idx])
        case .transport:
            // Offline. Don't extend the schedule — NetworkMonitor + the
            // pendingSnap retry handles getting back online. Keep current
            // nextAllowedAt; consecutive counter unchanged.
            break
        }
    }

    func recordSuccess() {
        consecutiveRateLimitFailures = 0
        nextAllowedAt = .distantPast
    }
}
