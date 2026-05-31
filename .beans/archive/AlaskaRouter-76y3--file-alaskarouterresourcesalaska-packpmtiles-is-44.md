---
# AlaskaRouter-76y3
title: File AlaskaRouter/Resources/alaska-pack.pmtiles is 447.27 MB; this exceeds GitHub's file size limit of 100.00 MB
status: completed
type: bug
priority: high
created_at: 2026-05-19T17:24:22Z
updated_at: 2026-05-20T10:23:50Z
parent: AlaskaRouter-xtua
---


## Summary of Changes

Picked the B+D hybrid (GitHub Releases + regenerate-from-OpenTopoMap script) over Git-LFS — see investigation notes below. Repo was cleaned and a Release-asset workflow set up.

**Cleanup:**
- git filter-repo --strip-blobs-bigger-than 25M evicted alaska-pack.pmtiles (447 MB) AND the older spike denali-otm.pmtiles (27 MB) from history.
- After GC: .git/ went from 717 MB to 15 MB.
- filter-repo auto-detached origin remote (standard safety behavior); need to re-add before pushing.
- 12 MB version of the spike denali-otm.pmtiles survived (under 25 MB threshold). Acceptable — under GitHub's 100 MB cap and only used by the dev spike.

**New workflow (tools/build-pack/):**
- fetch-pack.sh — download the latest data/alaska-* release asset into AlaskaRouter/Resources/. Verifies SHA-256 sidecar, skips download if local file matches. Idempotent.
- release-pack.sh — publish the local pmtiles + manifest as a release (uses gh CLI). Tag derived from manifest.version. Generates SHA sidecars so fetch-pack.sh can verify.
- README.md — documents the lifecycle + Xcode Run Script snippet for auto-fetch on build.
- download_tiles.py — unchanged; remains as the escape hatch for full regeneration from OpenTopoMap.

**gitignore:** *.pmtiles globally, with a comment pointing at fetch-pack.sh.

**Supersedes:** AlaskaRouter-6360 (Git-LFS for large binary assets) — closed as scrapped, hybrid Releases approach picked instead.
