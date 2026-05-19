---
# AlaskaRouter-nv50
title: Bundle manifest v2 schema
status: todo
type: feature
priority: normal
created_at: 2026-05-19T07:18:07Z
updated_at: 2026-05-19T07:18:07Z
parent: AlaskaRouter-ttvk
---

v1 has alaska-pack.manifest.json with schema_version=1 (region, version, bbox, byte_size, coverage, attribution). v2 needs: signed manifests, dependency tracking (this pack requires world-skeleton vN), update channels, optional checksum per tile. Should remain backwards-compatible with v1 packs.
