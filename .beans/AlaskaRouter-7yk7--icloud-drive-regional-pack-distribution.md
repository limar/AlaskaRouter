---
# AlaskaRouter-7yk7
title: iCloud Drive regional pack distribution
status: todo
type: feature
priority: high
created_at: 2026-05-19T07:17:51Z
updated_at: 2026-05-19T07:17:51Z
parent: AlaskaRouter-ttvk
---

v1 bundles alaska-pack.pmtiles (447MB) inside the app. v2 moves regional packs to iCloud Drive: the app ships only the world skeleton (~30MB z=0-5), and users download/import region packs at runtime via DocumentPicker. Requires bundle manifest schema, pack-management UI, sandboxed file access to ~/Library/Mobile Documents/.
