---
# AlaskaRouter-7i4o
title: Search bar polish — add clear button, drop mic button
status: todo
type: task
priority: high
created_at: 2026-05-24T09:55:56Z
updated_at: 2026-05-24T09:55:56Z
parent: AlaskaRouter-ka6b
---

User feedback (2026-05-24):
> add clear search bar text button (currently there is no easy way to delete the typed text), remove the microphone button (it does nothing and anyway duplicates the what we have on any keyboard)

## Scope

- Add a small \`xmark.circle.fill\` clear button at the trailing edge of the search field, visible only when \`query\` is non-empty.
- Tapping it clears \`searchService.setQuery(\"\")\` and keeps the field focused.
- Remove the \`mic.fill\` icon — it's decorative-only (no speech-to-text wired) and duplicates the iOS keyboard mic.

## Files

- AlaskaRouter/UI/FloatingSearchBar.swift

## Checklist

- [ ] Drop \`mic.fill\` from \`expandedPill\`
- [ ] Add \`xmark.circle.fill\` button trailing the TextField, visible when \`!query.isEmpty\`
- [ ] Verify clear button keeps focus + clears in one tap
- [ ] On-device check
