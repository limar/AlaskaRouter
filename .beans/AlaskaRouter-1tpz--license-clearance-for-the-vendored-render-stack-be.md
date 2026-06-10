---
# AlaskaRouter-1tpz
title: License clearance for the vendored render stack before OSS / App Store
status: todo
type: task
priority: normal
created_at: 2026-06-10T09:56:46Z
updated_at: 2026-06-10T09:56:46Z
---

## Why
We vendored tools/opentopomap-render/third_party/otm-docker/ (snapshot of github.com/lukey78/otm-docker @ a024111, fetched 2026-06-10) for build reproducibility. It has NO license (all rights reserved). The cartography in its assets/ comes from der-stefan/OpenTopoMap (license 'Other'/NOASSERTION). This is fine for our PRIVATE/build use, but is a GATE before the repo goes public (OSS) or we lean on it for App Store distribution.

## Before public/OSS release, do ONE of:
- [ ] Ask lukey78 (and/or der-stefan) for explicit permission / a license to redistribute, and record it.
- [ ] OR re-derive our own render image from der-stefan/OpenTopoMap (after reading its actual LICENSE) + the standard GPL/LGPL tools, so we don't republish the no-license snapshot.
- [ ] OR keep third_party/ out of the public repo (private submodule / not published).

## Separately (App Store, governed by the shipped TILES, not the build kitchen)
- [ ] In-app attribution/credits screen for OpenStreetMap (ODbL) + OpenTopoMap style (CC-BY-SA). Tiles are ShareAlike; ship them with attribution. (Confirm what the app already shows.)
- [ ] Read der-stefan/OpenTopoMap's actual LICENSE text (it's 'Other') and record the terms; relevant to modifying the style for the cartography work (AlaskaRouter-f7tt).

Not legal advice -- get a real license review before distribution.

## See
tools/opentopomap-render/third_party/otm-docker/PROVENANCE.md
