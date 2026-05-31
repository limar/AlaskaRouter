---
# AlaskaRouter-tsvw
title: 'Try: relocate the block-header collapse chevron to the trailing edge'
status: completed
type: task
priority: high
created_at: 2026-05-30T09:08:35Z
updated_at: 2026-05-30T09:33:17Z
parent: AlaskaRouter-e0vm
---

Current leading-edge chevron breaks the chip-to-pip indentation rhythm and crowds the leading side. TRY moving the chevron to the trailing edge, reusing the existing drag-handle slot: expanded → drag handle there as today; collapsed → chevron.right in the same slot (since collapsed blocks can't be dragged anyway per jhw8). Leading edge becomes just the colored chip.

Alternatives considered (recorded for later if (a) lands badly):
- (b) Drop the chevron entirely, whole-header tap still toggles — affordance becomes invisible.
- (c) Chevron INSIDE the colored chip replacing the number — loses the block-number-in-chip cue that mirrors map markers.

Accept criterion: leading edge of header is just the chip + name; collapsed state is still discoverable; tap-to-toggle still works.

## Summary
Disclosure chevron moved off the leading edge (was crowding the chip and breaking indentation rhythm). Now lives at the trailing edge, always visible — chevron.down expanded, chevron.right collapsed. First TRY (chevron only when collapsed) failed the discoverability bar; second TRY (always-visible) accepted by user. Block-header drag handle removed and block reordering disabled in the process — long-flagged 'not a real use case' (stops remain reorderable).
