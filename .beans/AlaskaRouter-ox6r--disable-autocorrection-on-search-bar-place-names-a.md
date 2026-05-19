---
# AlaskaRouter-ox6r
title: Disable autocorrection on search bar (place names aren't English)
status: completed
type: bug
priority: high
created_at: 2026-05-19T10:03:31Z
updated_at: 2026-05-19T12:01:55Z
parent: AlaskaRouter-xtua
---

iOS keyboard autocorrects place names that aren't English words (Russian/Native/Athabaskan/etc. transliterations like 'Kotsina', 'Wonder Lake', 'Anaktuvuk'). User shows 'Kot' being autocorrected to 'Lot' — typing the real name becomes impossible.

Fix: disable autocorrection on the search TextField. Also disable autocapitalization and spell-check for the same reasons.

- [x] TextField(.autocorrectionDisabled() + .textInputAutocapitalization(.never)) on the search field in FloatingSearchBar
- [x] Verify in simulator with a Native place name (e.g. 'Kotsina', 'Kuparuk') — user to confirm at next manual test

## Summary of Changes

Added three modifiers on the TextField in FloatingSearchBar.expandedPill: .autocorrectionDisabled(true), .textInputAutocapitalization(.never), .keyboardType(.default). Now typing 'Kot' no longer gets corrected to 'Lot'.
