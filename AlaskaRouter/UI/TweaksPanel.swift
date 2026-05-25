// In-app tweaks panel. Live design-iteration tool — slide values, see
// the map update immediately. Persisted via TweaksStore.
//
// Presented as a sheet from RootView via a small wrench button at the
// top-left of the map.

import SwiftUI

struct TweaksPanel: View {
    @Bindable var tweaks: TweaksStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    sliderRow(
                        label: "Default diameter",
                        value: $tweaks.dotDiameterDefault,
                        range: 16...60, step: 1, format: "%.0f pt"
                    )
                    sliderRow(
                        label: "Selected diameter",
                        value: $tweaks.dotDiameterSelected,
                        range: 20...72, step: 1, format: "%.0f pt"
                    )
                    sliderRow(
                        label: "Font weight",
                        value: $tweaks.dotFontWeight,
                        range: 0.0...0.62, step: 0.02,
                        format: "%.2f",
                        annotations: [
                            (0.0,  "reg"), (0.23, "med"), (0.30, "semi"),
                            (0.40, "bold"), (0.56, "heavy"), (0.62, "black"),
                        ]
                    )
                    sliderRow(
                        label: "Font size",
                        value: $tweaks.dotFontSizeRatio,
                        range: 0.30...0.80, step: 0.01,
                        format: "%.2f × diameter"
                    )
                } header: {
                    Text("Waypoint Dot")
                } footer: {
                    Text("Values persist across launches. Tap reset to revert to v1 defaults.")
                        .font(.footnote)
                }

                Section {
                    Toggle("Loose matcher", isOn: $tweaks.useLooseMatcher)
                } header: {
                    Text("Search")
                } footer: {
                    Text("When ON, search retries with synonyms (bike↔motorcycle, sign↔wayside, ferry↔ferries, …) and drops descriptor tokens (\"ferry\", \"sign\", \"the\", …) if the strict query returns nothing. Catches \"Ferry Whittier\" → Whittier Terminal, \"Arctic Circle Sign\" → Arctic Circle Wayside. Flip OFF to compare against the original strict behavior.")
                        .font(.footnote)
                }

                Section {
                    Picker("Marker style", selection: $tweaks.placeMarkerStyle) {
                        Text("0 — Filled (iter 3)").tag(0)
                        Text("1 — Outline + cream halo").tag(1)
                        Text("2 — Smaller + translucent").tag(2)
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Place markers (vyfe spike)")
                } footer: {
                    Text("Visual A/B for the place-marker icons. Pick a variant, then close this sheet — the map re-registers icons on the next pan/zoom. \"0\" is the heavy filled iteration 3; \"1\" is the candidate (stroked colored shape on a cream halo, matching the labels' aesthetic); \"2\" is a faded smaller filled. Lock the winner when you've decided.")
                        .font(.footnote)
                }

                Section {
                    Button("Reset to defaults", role: .destructive) {
                        tweaks.resetToDefaults()
                    }
                }
            }
            .navigationTitle("Tweaks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// A labeled slider row with the current value shown on the trailing
    /// edge and optional named-anchor annotations beneath (handy for the
    /// font-weight slider where pure numbers are meaningless).
    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String,
        annotations: [(Double, String)]? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
            if let annotations {
                HStack {
                    ForEach(annotations, id: \.0) { (val, name) in
                        Button {
                            value.wrappedValue = val
                        } label: {
                            Text(name)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    abs(value.wrappedValue - val) < step / 2
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.secondary.opacity(0.08)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                    Spacer()
                }
            }
        }
    }
}
