// Offline map-snapshot renderer for the export share-sheet preview
// (AlaskaRouter-56kj).
//
// The top of the iOS share sheet is a PREVIEW of the document. We render that
// preview as a square map snapshot centered on the trip's first waypoint, using
// MLNMapSnapshotter with the SAME offline style (`styleURL`) the live map uses —
// so it renders from the bundled PMTiles with no network — then composite a
// waypoint marker + name pill on top.
//
// RENDERS ARE SERIALIZED — one snapshotter at a time, newest request wins.
// Two MLNMapSnapshotters with equal ResourceOptions are handed the *same*
// PMTilesFileSource by MapLibre's FileSourceManager, and concurrent first-time
// reads corrupt its shared directory cache: the render fails with "Error
// parsing PMTiles directory" and the share sheet silently falls back to the app
// icon (AlaskaRouter-pq9g — measured 1/12 launches OK with two overlapping
// renders, 44/44 once serialized). The live MapView is not a participant; a
// lone snapshotter never failed in 24 runs.
//
// PreviewRenderSlot owns those rules; everything MapLibre-shaped lives in the
// `start` closure below.

// MapLibre is a pre-concurrency Objective-C module: none of its types carry
// Sendable annotations, so `@preconcurrency` is what lets us hold an
// MLNMapSnapshotter across its own callback without the compiler speculating
// about isolation the framework never declared.
@preconcurrency import MapLibre
import Foundation
import CoreLocation
import UIKit

@MainActor
enum TripPreviewRenderer {
    /// Render a square offline map snapshot centered on `center` and composite
    /// a waypoint marker (+ optional name pill) over it. Calls back on the main
    /// thread with the finished preview image (or nil on failure).
    static func renderPreview(
        center: CLLocationCoordinate2D,
        name: String?,
        markerColor: UIColor,
        zoom: Double = 8.5,
        size: CGSize = CGSize(width: 600, height: 600),
        completion: @escaping @MainActor (UIImage?) -> Void
    ) {
        snapshot(center: center, zoom: zoom, size: size) { image in
            guard let image else { completion(nil); return }
            completion(compose(snapshot: image, name: name, markerColor: markerColor))
        }
    }

    /// Serializes renders: one at a time, and a newer request cancels the one
    /// running rather than waiting behind it.
    private static let slot = PreviewRenderSlot { job, finished in
        let camera = MLNMapCamera()
        camera.centerCoordinate = job.center
        let options = MLNMapSnapshotOptions(styleURL: styleURL, camera: camera, size: job.size)
        options.zoomLevel = job.zoom

        let snapshotter = MLNMapSnapshotter(options: options)
        snapshotter.start { snapshot, error in
            let image = snapshot?.image
            // `startWithCompletionHandler:` is documented to run the handler on
            // the main queue, but MapLibre predates Swift concurrency so the
            // block imports as non-isolated. assumeIsolated states the contract
            // the framework already guarantees; hopping instead would push the
            // callback into a later turn for no reason.
            MainActor.assumeIsolated {
                if let error {
                    print("[TripPreviewRenderer] snapshot error: \(error)")
                }
                finished(image)
            }
        }
        return { snapshotter.cancel() }
    }

    /// Raw offline basemap snapshot (no overlay). Every completion is called
    /// exactly once, on the main thread — with nil if the snapshot failed, and
    /// also with nil if a newer request superseded this one.
    static func snapshot(
        center: CLLocationCoordinate2D,
        zoom: Double = 8.5,
        size: CGSize = CGSize(width: 600, height: 600),
        completion: @escaping @MainActor (UIImage?) -> Void
    ) {
        slot.submit(
            PreviewRenderSlot.Job(center: center, zoom: zoom, size: size),
            completion: completion
        )
    }

    /// Draw a centered waypoint marker and an optional name pill over the map.
    /// Sizes are proportional to the image width so the marker/label stay
    /// legible when the share sheet scales the thumbnail down.
    private static func compose(snapshot: UIImage, name: String?, markerColor: UIColor) -> UIImage {
        let size = snapshot.size
        let w = size.width
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = snapshot.scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            snapshot.draw(in: CGRect(origin: .zero, size: size))

            let center = CGPoint(x: w / 2, y: size.height / 2)
            func disc(radius: CGFloat, color: UIColor, shadow: Bool = false) {
                if shadow {
                    cg.setShadow(offset: CGSize(width: 0, height: w * 0.004),
                                 blur: w * 0.012,
                                 color: UIColor.black.withAlphaComponent(0.35).cgColor)
                }
                color.setFill()
                cg.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
                if shadow { cg.setShadow(offset: .zero, blur: 0, color: nil) }
            }
            // White ring → colored disc → white center (app waypoint style).
            disc(radius: w * 0.050, color: .white, shadow: true)
            disc(radius: w * 0.040, color: markerColor)
            disc(radius: w * 0.014, color: .white)

            guard let name, !name.isEmpty else { return }
            let font = UIFont.systemFont(ofSize: w * 0.052, weight: .semibold)
            let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let textSize = (name as NSString).size(withAttributes: textAttrs)
            let padH = w * 0.028, padV = w * 0.014
            let pillW = min(w - w * 0.08, textSize.width + padH * 2)
            let pillH = textSize.height + padV * 2
            let pillRect = CGRect(x: center.x - pillW / 2, y: center.y + w * 0.045,
                                  width: pillW, height: pillH)
            UIColor.black.withAlphaComponent(0.72).setFill()
            UIBezierPath(roundedRect: pillRect, cornerRadius: pillH / 2).fill()

            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.lineBreakMode = .byTruncatingTail
            var labelAttrs = textAttrs
            labelAttrs[.paragraphStyle] = para
            (name as NSString).draw(
                in: pillRect.insetBy(dx: padH, dy: padV),
                withAttributes: labelAttrs)
        }
    }
}
