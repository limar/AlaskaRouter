// One preview render at a time, newest request wins (AlaskaRouter-pq9g).
//
// Split out of TripPreviewRenderer so these rules can be exercised without
// MapLibre: `start` is the only thing that touches a snapshotter, and tests
// substitute their own (AlaskaRouter-9b5o).
//
// Two measured facts from MapLibre shape this:
//
//   - Concurrent snapshotters corrupt the shared PMTiles directory cache, so
//     exactly one render may be in flight (AlaskaRouter-pq9g).
//   - `MLNMapSnapshotter.cancel()` is SILENT: a cancelled render never calls
//     its completion handler. So the slot must settle abandoned requests
//     itself, or a caller waits forever.
//
// A newer request CANCELS the running render rather than waiting behind it: a
// render takes ~190-320 ms and a superseded preview is worthless, so finishing
// it would just burn the render and hand the UI an image it is about to
// replace. The trade is that a caller submitting faster than renders complete
// starves — acceptable here, where requests come from trip edits and the
// preview only has to be right once the user opens the share sheet.

import CoreLocation
import Foundation
import UIKit

@MainActor
final class PreviewRenderSlot {
    struct Job {
        let center: CLLocationCoordinate2D
        let zoom: Double
        let size: CGSize
    }

    /// Cancels the running render. Afterwards its `finished` callback will not
    /// be called — the slot settles the request instead.
    typealias Cancel = @MainActor () -> Void

    /// Starts a render, calling `finished` when it completes, and returns its
    /// cancel handle. A late `finished` from a cancelled render is ignored.
    typealias Start = (_ job: Job, _ finished: @escaping @MainActor (UIImage?) -> Void) -> Cancel

    private struct Entry {
        let job: Job
        let completion: @MainActor (UIImage?) -> Void
    }

    private let start: Start
    private var running: Entry?
    private var cancelRunning: Cancel?
    /// Distinguishes the render we are waiting on from one we abandoned, so a
    /// cancelled render whose callback was already in flight can't settle a
    /// request twice.
    private var generation = 0

    init(start: @escaping Start) {
        self.start = start
    }

    /// Submit a render, superseding whatever is running. Every completion is
    /// called exactly once: with the image, or with nil if the render failed
    /// or was superseded.
    func submit(_ job: Job, completion: @escaping @MainActor (UIImage?) -> Void) {
        let superseded = running
        cancelRunning?()
        running = nil
        cancelRunning = nil
        generation += 1          // any callback still in flight is now stale
        superseded?.completion(nil)

        run(Entry(job: job, completion: completion))
    }

    private func run(_ entry: Entry) {
        generation += 1
        let generation = self.generation
        running = entry
        let cancel = start(entry.job) { [weak self] image in
            guard let self, generation == self.generation else { return }
            self.running = nil
            self.cancelRunning = nil
            entry.completion(image)
        }
        // Skipped if `start` already settled or superseded this render.
        if generation == self.generation, running != nil {
            cancelRunning = cancel
        }
    }
}
