---
# AlaskaRouter-prlm
title: Back up & restore trips online (survive a reinstall)
status: todo
type: feature
priority: normal
created_at: 2026-07-27T22:41:21Z
updated_at: 2026-07-27T22:51:08Z
parent: AlaskaRouter-36of
---

From the Alaska field trip, July 2026. Trips live only in the local SwiftData store. Reinstall the app — or lose the phone — and the trips are gone.

## What is wanted
Trips preserved somewhere off-device, and restored after a reinstall.

## Options to weigh (this is the discussion)
- **CloudKit / SwiftData automatic sync.** Native, no server, syncs across the user's own devices, survives reinstall on the same Apple ID. Costs: the SwiftData model needs to be CloudKit-compatible (all-optional or defaulted properties, no unique constraints) — and AlaskaRouter-tpoo already records unresolved store-migration trouble, so this is not free. Locks the feature to Apple accounts.
- **iCloud Drive documents.** We already have a lossless trip file format (`.akrtrip`, AlaskaRouter-h113) and already use iCloud Drive for the regional map packs — so the plumbing and the mental model both exist. Simplest honest option: trips as files the user can see, copy, and mail. Not real-time sync; more of a backup.
- **Manual export as it stands.** Already shipped — arguably the feature is "make it automatic and unmissable" rather than anything new.
- **Own server / third-party DB.** Rejected on sight for a personal, offline-first, OSS-leaning app with no subscription: it means accounts, hosting and a privacy policy.

Recommendation to beat: **iCloud Drive `.akrtrip` documents with an automatic write on change**, because it reuses two things that already work and keeps the data in a form the user owns. Real CloudKit sync is the v2+ answer if multi-device editing ever matters.

## To decide
- Backup (one-way, restore on demand) or sync (two-way, multi-device)? They are very different amounts of work.
- Automatic or user-triggered?
- What happens on restore when a trip already exists — merge, duplicate, or replace?
