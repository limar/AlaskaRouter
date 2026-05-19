---
# AlaskaRouter-rwbc
title: Multi-region search (combine FTS5 DBs across packs)
status: todo
type: feature
priority: normal
created_at: 2026-05-19T07:18:02Z
updated_at: 2026-05-19T07:18:02Z
parent: AlaskaRouter-ttvk
---

v1 has one bundled alaska-places.sqlite (12,617 FTS5 places). v2 needs to combine FTS5 databases across installed regional packs into a single searchable corpus. Options: ATTACH multiple SQLite DBs and UNION queries, or build a meta-index. Must preserve sub-5ms query latency and the two-stage retrieval design.
