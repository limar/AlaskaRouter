// Visual spike for AlaskaRouter-dzhp — callout title legibility.
//
// Renders the candidate title treatments over a real map backdrop (a
// screenshot of the shipping app), so `.thinMaterial` and the type are judged
// against the surface they actually sit on rather than a flat colour.
//
// The callout body below is copied verbatim from StopCallout.swift, with only
// the data type swapped for a plain struct (the real one takes a SwiftData
// `Waypoint`, which would drag the whole model layer in).
//
// Round 1 established two things that are NOT obvious from reading the code:
//   * `lineLimit(n)` alone does nothing in this layout — the title stays on
//     one line and truncates. `fixedSize(horizontal:false, vertical:true)` is
//     required for any wrapping to happen at all.
//   * A wrapped title needs `.firstTextBaseline` icon alignment, or the
//     category icon drifts to the vertical middle and reads as detached.
//
// Round 2 (this file) explores the user's two follow-ups: more than 2 lines,
// and moving the title out from beside the "…"/"✕" button column so it can use
// the callout's full width.
//
// Launch args: -nameIndex N   which hard Alaska name to render
//              -page N        which comparison set (0 or 1)

import SwiftUI

@main
struct CalloutSpikeApp: App {
    var body: some Scene {
        WindowGroup { SpikeView() }
    }
}

// MARK: - Test data

/// The names that actually broke in the field, worst first. Index 5 is a
/// pathological control, longer than anything in the trip.
let hardNames: [String] = [
    "Arctic Interagency Visitor Center",
    "Galbraith Lake Campground",
    "The Inn at Coldfoot Camp",
    "Marion Creek Campground",
    "Coldfoot",
    "Arctic Interagency Visitor Center at Coldfoot",
]

let hardCategories: [String] = [
    "visitor_center", "camping", "lodging", "camping", "fuel", "visitor_center",
]

// MARK: - Variants

/// Where the title sits relative to the "…" / "✕" button column.
enum TitleLayout {
    /// Shipping today: title shares its row with the buttons, so it only gets
    /// ~174pt of the callout's 272pt content width.
    case besideButtons
    /// Buttons move up onto the "STOP 3 OF 5" line; the title gets its own
    /// full-width row beneath them — ~254pt, about 46% more.
    case fullWidthBelow
}

/// How the title decides its own size.
enum TitleStrategy {
    /// One fixed treatment: `lineLimit` lines, shrinking no further than
    /// `minScale` only if that budget is exceeded.
    case fixed(lineLimit: Int, minScale: CGFloat)
    /// The two-step heuristic: prefer ONE line at full size; if the name
    /// cannot fit on one line, drop to `fallbackScale` of the base size and
    /// allow up to `fallbackLines`, ellipsizing the last. Implemented with
    /// `ViewThatFits`, which picks the first candidate whose ideal width fits
    /// and otherwise falls through to the last.
    case preferOneLine(fallbackScale: CGFloat, fallbackLines: Int)
    /// Same two-step shape, but the fallback keeps full size and only shrinks
    /// as far as it must. Included to test whether the hard drop to 75% is
    /// worth it, or whether it costs type size for nothing.
    case preferOneLineSoft(minScale: CGFloat, fallbackLines: Int)
}

struct Variant: Identifiable {
    let id: String
    let label: String
    let layout: TitleLayout
    let strategy: TitleStrategy
}

let allVariants: [Variant] = [
    Variant(id: "A", label: "A — today: beside buttons, 1 line",
            layout: .besideButtons, strategy: .fixed(lineLimit: 1, minScale: 1.0)),
    Variant(id: "G", label: "G — beside buttons, up to 4 lines",
            layout: .besideButtons, strategy: .fixed(lineLimit: 4, minScale: 1.0)),
    Variant(id: "H", label: "H — beside buttons, 2 lines + shrink 75%",
            layout: .besideButtons, strategy: .fixed(lineLimit: 2, minScale: 0.75)),
    Variant(id: "E", label: "E — FULL WIDTH below buttons, up to 2 lines",
            layout: .fullWidthBelow, strategy: .fixed(lineLimit: 2, minScale: 1.0)),
    Variant(id: "F", label: "F — FULL WIDTH below buttons, up to 4 lines",
            layout: .fullWidthBelow, strategy: .fixed(lineLimit: 4, minScale: 1.0)),
    Variant(id: "J", label: "J — 1 line @100%, else 75% + up to 4 lines",
            layout: .besideButtons,
            strategy: .preferOneLine(fallbackScale: 0.75, fallbackLines: 4)),
    Variant(id: "K", label: "K — 1 line @100%, else up to 4 lines, shrink only if needed",
            layout: .besideButtons,
            strategy: .preferOneLineSoft(minScale: 0.75, fallbackLines: 4)),
    Variant(id: "L", label: "L — 1 line @100%, else 85% (14.5pt) + up to 4 lines",
            layout: .besideButtons,
            strategy: .preferOneLine(fallbackScale: 0.85, fallbackLines: 4)),
]

/// Page 0 isolates "more lines / more shrink" at today's width.
/// Page 1 isolates the structural change, with A as the shared anchor.
/// Page 2 is the two-step heuristic, hard drop vs soft shrink.
let pages: [[String]] = [
    ["A", "G", "H"],
    ["A", "E", "F"],
    ["A", "J", "K"],
    // Page 3: the fallback size is the whole remaining question — 75% vs 85%
    // vs "keep 17pt and just take another line".
    ["J", "L", "K"],
]

// MARK: - Spike screen

struct SpikeView: View {
    private var nameIndex: Int {
        min(max(UserDefaults.standard.integer(forKey: "nameIndex"), 0), hardNames.count - 1)
    }
    private var page: Int {
        min(max(UserDefaults.standard.integer(forKey: "page"), 0), pages.count - 1)
    }
    private var variants: [Variant] {
        pages[page].compactMap { id in allVariants.first { $0.id == id } }
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Image("backdrop")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            VStack(spacing: 12) {
                ForEach(variants) { variant in
                    VStack(spacing: 5) {
                        Text(variant.label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.6), in: Capsule())
                        SpikeStopCallout(
                            name: hardNames[nameIndex],
                            category: hardCategories[nameIndex],
                            variant: variant
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Callout under test (StopCallout body, title treatment swapped)

struct SpikeStopCallout: View {
    let name: String
    let category: String
    let variant: Variant

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch variant.layout {
            case .besideButtons: besideButtonsHeader
            case .fullWidthBelow: fullWidthHeader
            }

            Divider().opacity(0.4)

            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                Text("Open in…")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: 300)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
    }

    // Shipping layout: the title competes with the button column for width.
    private var besideButtonsHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                positionLabel
                titleRow
                detailLines
            }
            Spacer(minLength: 4)
            buttons
        }
    }

    // Proposed layout: buttons ride the position label, title gets its own row.
    private var fullWidthHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                positionLabel
                Spacer(minLength: 4)
                buttons
            }
            titleRow
            detailLines
        }
    }

    private var positionLabel: some View {
        Text("STOP 3 OF 5")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(1.2)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.thinMaterial, in: Circle())
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.thinMaterial, in: Circle())
        }
    }

    private var titleRow: some View {
        // firstTextBaseline throughout: it reads the same as centre for a
        // single line, and is the only thing that keeps the icon attached to
        // the name once the title wraps. With ViewThatFits we cannot know
        // statically whether it wrapped, so it has to be right for both.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: CategorySymbol.name(for: category))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            title
        }
    }

    @ViewBuilder
    private var detailLines: some View {
        Text(CategoryLabel.display(category))
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        Text("170 km from previous")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        Text("94 km to next")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private static let baseSize: CGFloat = 17

    /// The thing under test. `fixedSize(horizontal:false, vertical:true)` is
    /// mandatory for any wrapping — without it `lineLimit` silently no-ops in
    /// this layout (measured in round 1, not assumed).
    @ViewBuilder
    private var title: some View {
        switch variant.strategy {
        case let .fixed(lineLimit, minScale):
            if lineLimit > 1 {
                titleText(size: Self.baseSize)
                    .lineLimit(lineLimit)
                    .minimumScaleFactor(minScale)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                titleText(size: Self.baseSize)
                    .lineLimit(1)
                    .minimumScaleFactor(minScale)
            }

        case let .preferOneLine(fallbackScale, fallbackLines):
            ViewThatFits(in: .horizontal) {
                // Candidate 1: one line at full size. `fixedSize()` makes its
                // ideal width the whole string, so ViewThatFits rejects it the
                // moment the name is too long for the row.
                titleText(size: Self.baseSize).lineLimit(1).fixedSize()
                // Candidate 2 is last, so it is always accepted.
                titleText(size: Self.baseSize * fallbackScale)
                    .lineLimit(fallbackLines)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .preferOneLineSoft(minScale, fallbackLines):
            ViewThatFits(in: .horizontal) {
                titleText(size: Self.baseSize).lineLimit(1).fixedSize()
                titleText(size: Self.baseSize)
                    .lineLimit(fallbackLines)
                    .minimumScaleFactor(minScale)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func titleText(size: CGFloat) -> Text {
        Text(name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.primary)
    }
}
