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
                        Text("0 — Filled (baseline)").tag(0)
                        Text("1 — Outline + cream halo").tag(1)
                        Text("2 — Translucent (no halo)").tag(2)
                        Text("3 — Translucent + cream halo  ✓").tag(3)
                    }
                    .pickerStyle(.inline)
                    sliderRow(
                        label: "Label size",
                        value: $tweaks.labelSizeMultiplier,
                        range: 0.70...1.50, step: 0.05,
                        format: "%.2f ×"
                    )
                } header: {
                    Text("Map labels & markers")
                } footer: {
                    Text("Variant 3 is the locked vyfe winner (translucent SF Symbols + cream halo); the others stay as A/B for future iteration. The label-size slider multiplies every map text-size at runtime (all curated tier labels + all places-tier-* labels). 1.0 = the values declared in style-base.json.")
                        .font(.footnote)
                }

                Section {
                    Picker("Style", selection: $tweaks.cancelButtonStyle) {
                        Text("0 — Plain text").tag(0)
                        Text("1 — Filled chip").tag(1)
                        Text("2 — Outlined chip").tag(2)
                    }
                    .pickerStyle(.inline)
                    Picker("Color", selection: $tweaks.cancelButtonColor) {
                        Text("0 — Slate blue").tag(0)
                        Text("1 — Brand blue").tag(1)
                        Text("2 — System blue").tag(2)
                        Text("3 — Charcoal").tag(3)
                        Text("4 — Secondary gray").tag(4)
                        Text("5 — Teal").tag(5)
                        Text("6 — System red").tag(6)
                    }
                    .pickerStyle(.menu)
                    Picker("Font weight", selection: $tweaks.cancelButtonFontWeight) {
                        Text("0 — regular").tag(0)
                        Text("1 — medium").tag(1)
                        Text("2 — semibold").tag(2)
                        Text("3 — bold").tag(3)
                        Text("4 — heavy").tag(4)
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Search bar Cancel button")
                } footer: {
                    Text("Replaces the AK chip when the search field is focused (y7l0 spike). Slate-blue filled chip is the initial recommendation — cool counterpart to the warm AK and \"+\" buttons. Try all combinations on-device; once locked, the tweaks get stripped and the chosen combo becomes the constant default.")
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
