// Rules of the preview render slot (AlaskaRouter-9b5o), exercised with a fake
// renderer so nothing here touches MapLibre or the PMTiles archive.
//
// The contract under test: one render at a time, a newer request cancels the
// running one, and every completion is called exactly once — because
// MLNMapSnapshotter.cancel() is silent, a request the slot abandons is one the
// slot must settle itself.

import CoreLocation
import UIKit
import XCTest
@testable import AlaskaRouter

@MainActor
final class PreviewRenderSlotTests: XCTestCase {
    /// A stand-in renderer: records what was started, finishes only when the
    /// test says so, and counts cancels.
    @MainActor
    private final class FakeRenderer {
        private(set) var started: [PreviewRenderSlot.Job] = []
        private(set) var cancels = 0
        private var finishers: [@MainActor (UIImage?) -> Void] = []

        var start: PreviewRenderSlot.Start {
            { [self] job, finished in
                started.append(job)
                finishers.append(finished)
                return { [self] in cancels += 1 }
            }
        }

        /// Complete the render started at `index` (default: the latest).
        func finish(_ index: Int? = nil, with image: UIImage? = UIImage()) {
            let i = index ?? finishers.count - 1
            finishers[i](image)
        }
    }

    private func job(_ lat: Double) -> PreviewRenderSlot.Job {
        PreviewRenderSlot.Job(
            center: CLLocationCoordinate2D(latitude: lat, longitude: -151),
            zoom: 8.5,
            size: CGSize(width: 600, height: 600)
        )
    }

    func testFirstRequestStartsImmediately() {
        let fake = FakeRenderer()
        let slot = PreviewRenderSlot(start: fake.start)

        slot.submit(job(1)) { _ in }

        XCTAssertEqual(fake.started.map(\.center.latitude), [1])
        XCTAssertEqual(fake.cancels, 0)
    }

    func testNewerRequestCancelsTheRunningRenderAndStartsAtOnce() {
        let fake = FakeRenderer()
        let slot = PreviewRenderSlot(start: fake.start)

        slot.submit(job(1)) { _ in }
        slot.submit(job(2)) { _ in }

        XCTAssertEqual(fake.cancels, 1)
        XCTAssertEqual(fake.started.map(\.center.latitude), [1, 2])
    }

    func testSupersededRequestIsSettledWithNil() {
        let fake = FakeRenderer()
        let slot = PreviewRenderSlot(start: fake.start)
        var superseded: UIImage? = UIImage()
        var settled = false

        slot.submit(job(1)) { image in superseded = image; settled = true }
        slot.submit(job(2)) { _ in }

        XCTAssertTrue(settled, "an abandoned request must not be left hanging")
        XCTAssertNil(superseded)
    }

    func testEveryCompletionIsCalledExactlyOnce() {
        let fake = FakeRenderer()
        let slot = PreviewRenderSlot(start: fake.start)
        var counts = [0, 0, 0]

        slot.submit(job(1)) { _ in counts[0] += 1 }
        slot.submit(job(2)) { _ in counts[1] += 1 }
        slot.submit(job(3)) { _ in counts[2] += 1 }
        fake.finish()

        XCTAssertEqual(counts, [1, 1, 1])
    }

    func testLateCallbackFromCancelledRenderIsIgnored() {
        let fake = FakeRenderer()
        let slot = PreviewRenderSlot(start: fake.start)
        var counts = [0, 0]

        slot.submit(job(1)) { _ in counts[0] += 1 }
        slot.submit(job(2)) { _ in counts[1] += 1 }
        // The cancelled render's callback was already in flight and lands anyway.
        fake.finish(0)

        XCTAssertEqual(counts, [1, 0], "a stale callback must not settle anyone twice")

        fake.finish(1)
        XCTAssertEqual(counts, [1, 1])
    }

    func testRenderedImageReachesItsOwnCompletion() {
        let fake = FakeRenderer()
        let slot = PreviewRenderSlot(start: fake.start)
        let image = UIImage()
        var received: UIImage?

        slot.submit(job(1)) { received = $0 }
        fake.finish(with: image)

        XCTAssertIdentical(received, image)
    }

    func testFailedRenderFreesTheSlot() {
        let fake = FakeRenderer()
        let slot = PreviewRenderSlot(start: fake.start)
        var results: [UIImage?] = []

        slot.submit(job(1)) { results.append($0) }
        fake.finish(with: nil)   // the render failed
        slot.submit(job(2)) { results.append($0) }

        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0])
        XCTAssertEqual(fake.started.count, 2, "a failed render must not wedge the slot")
        XCTAssertEqual(fake.cancels, 0, "nothing was running, so nothing to cancel")
    }

    func testCompletedRenderIsNotCancelledByTheNextRequest() {
        let fake = FakeRenderer()
        let slot = PreviewRenderSlot(start: fake.start)

        slot.submit(job(1)) { _ in }
        fake.finish()
        slot.submit(job(2)) { _ in }

        XCTAssertEqual(fake.cancels, 0)
        XCTAssertEqual(fake.started.map(\.center.latitude), [1, 2])
    }
}
