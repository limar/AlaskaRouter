---
# AlaskaRouter-xq6w
title: 'Spike: collapsible blocks UI (native Sections vs flat+chevron)'
status: completed
type: task
priority: high
created_at: 2026-05-29T17:37:33Z
updated_at: 2026-05-29T18:37:20Z
---

Explore Option 3 (native SwiftUI Section(isExpanded:)) for collapsing itinerary blocks in the bottom sheet, vs Option 1 (flat List + chevron + filter). Standalone spike so we can SEE/feel it before deciding.

## Spike
- spikes/D_collapse: pure-SwiftUI iOS app (no MapLibre/SwiftData), dummy multi-day itinerary.
- Two modes (segmented picker + `-mode` launch arg): "Native Sections" and "Flat + chevron".
- Demonstrates collapse animation, system chevron, plain-style sticky headers, and the reorder difference (native = within-section only; flat = cross-block).
- New CollapseSpike app target in project.yml (throwaway).

## Tasks
- [x] Write spike SwiftUI (model + both modes, approximate sheet styling)
- [x] Add CollapseSpike target, generate, build, run on simulator
- [x] Screenshot both modes — /tmp/collapse-native.png, /tmp/collapse-flat.png
- [x] Decide Option 1 vs 3 for the real implementation → **Option 1 (flat + chevron)**, confirmed by user ("clear win").

## Findings (spike)
Native Section(isExpanded:): collapse works but List mutes the custom header to grey, the disclosure affordance is unclear in plain style, headers pin/stick on scroll, and .onMove is within-section only (cross-day reorder would need custom drag-and-drop). Flat List + custom chevron: full control over header look, matches the real sheet, withAnimation gives a smooth fold, and the existing flat cross-block reorder is preserved. → recommend Option 1 (flat + chevron) for the real implementation.

## Decision
Option 1 (flat List + custom chevron + filter) wins on look (matches sheet), control, and preserves the existing cross-block reorder. Implementation tracked in a separate feature bean. Spike target (CollapseSpike) + spikes/D_collapse remain for reference; can be removed later.

## Cleanup
Spike target + spikes/D_collapse removed after the decision (Option 1 shipped in AlaskaRouter-6wrq).
