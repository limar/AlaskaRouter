// Unit tests for the routing exponential-backoff policy (AlaskaRouter-41no).

import XCTest
@testable import AlaskaRouter

@MainActor
final class RoutingRetryPolicyTests: XCTestCase {

    /// A tiny clock the policy reads instead of `Date.now`, so tests don't
    /// have to wait wallclock seconds for the schedule to elapse.
    final class TestClock {
        var now: Date
        init(now: Date) { self.now = now }
    }

    private func makePolicy(clock: TestClock) -> RoutingRetryPolicy {
        RoutingRetryPolicy(now: { clock.now })
    }

    func testFreshPolicyAllowsImmediateFire() {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000_000))
        let policy = makePolicy(clock: clock)
        XCTAssertTrue(policy.canFireNow)
        XCTAssertEqual(policy.secondsUntilNextAllowed, 0)
    }

    func testRateLimitedFailureBlocksUntilFirstScheduleEntry() {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000_000))
        let policy = makePolicy(clock: clock)
        policy.recordFailure(kind: .rateLimited)
        XCTAssertFalse(policy.canFireNow)
        XCTAssertEqual(policy.secondsUntilNextAllowed, RoutingRetryPolicy.schedule[0], accuracy: 0.001)
    }

    func testFiveConsecutiveFailuresWalkTheSchedule() {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000_000))
        let policy = makePolicy(clock: clock)
        for (i, expectedDelay) in RoutingRetryPolicy.schedule.enumerated() {
            policy.recordFailure(kind: .rateLimited)
            XCTAssertEqual(
                policy.secondsUntilNextAllowed,
                expectedDelay,
                accuracy: 0.001,
                "failure #\(i + 1) should set next-allowed to schedule[\(i)] = \(expectedDelay)s"
            )
            // Advance clock past this window for the next iteration.
            clock.now = clock.now.addingTimeInterval(expectedDelay)
        }
    }

    func testFailuresBeyondScheduleHoldAtMaximum() {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000_000))
        let policy = makePolicy(clock: clock)
        let max = RoutingRetryPolicy.schedule.last!
        for _ in 0 ..< (RoutingRetryPolicy.schedule.count + 3) {
            policy.recordFailure(kind: .rateLimited)
        }
        XCTAssertEqual(policy.secondsUntilNextAllowed, max, accuracy: 0.001)
    }

    func testSuccessResetsCounterAndUnblocksImmediately() {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000_000))
        let policy = makePolicy(clock: clock)
        policy.recordFailure(kind: .rateLimited)
        policy.recordFailure(kind: .rateLimited)
        XCTAssertFalse(policy.canFireNow)
        policy.recordSuccess()
        XCTAssertTrue(policy.canFireNow)
        XCTAssertEqual(policy.consecutiveRateLimitFailures, 0)
    }

    func testTransportFailureDoesNotAdvanceSchedule() {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000_000))
        let policy = makePolicy(clock: clock)
        policy.recordFailure(kind: .transport)
        XCTAssertTrue(policy.canFireNow, "transport failures don't gate retries; NetworkMonitor handles reconnect")
        XCTAssertEqual(policy.consecutiveRateLimitFailures, 0)
    }

    func testWindowReopensWhenClockAdvances() {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000_000))
        let policy = makePolicy(clock: clock)
        policy.recordFailure(kind: .rateLimited)
        XCTAssertFalse(policy.canFireNow)
        clock.now = clock.now.addingTimeInterval(RoutingRetryPolicy.schedule[0] + 0.001)
        XCTAssertTrue(policy.canFireNow)
    }
}
