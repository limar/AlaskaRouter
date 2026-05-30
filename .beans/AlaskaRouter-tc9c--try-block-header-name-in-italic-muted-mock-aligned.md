---
# AlaskaRouter-tc9c
title: 'Try: block-header name in italic + muted (mock-aligned typography)'
status: completed
type: task
priority: high
created_at: 2026-05-30T09:35:26Z
updated_at: 2026-05-30T09:43:12Z
parent: AlaskaRouter-e0vm
---

Mock's BlockHeader uses italic + muted color for the auto-generated 'A → B' name (different 'voice' from waypoint names which are solid serif semibold). Same family, same size, just italic style + muted shade. Makes the section header read as a quiet label rather than a competing primary line — and visually distinguishes it from waypoint rows.

## Try
- Text(displayName) → add .italic(), change foregroundStyle from textStrong to textMuted (or a slightly stronger muted if textMuted feels too faded).
- Subline ('N stops · X km') already matches mock; no change.
- Size stays at 14pt for now (mock matches); revisit if italic at 14 feels off.

Accept criterion: block headers visually quieter, no longer compete with stop names for attention; trip still scannable.

## Summary
Block-header name → italic + muted serif (same family, same size, same weight; just italic style + textMuted shade). Distinguishes section labels from waypoint names. User accepted with a flag — see AlaskaRouter-xnkv for the cross-cutting translucency/contrast issue.
