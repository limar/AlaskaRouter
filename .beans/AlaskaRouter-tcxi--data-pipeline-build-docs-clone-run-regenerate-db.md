---
# AlaskaRouter-tcxi
title: Data-pipeline build docs (clone → run → regenerate DB)
status: completed
type: task
priority: high
created_at: 2026-06-02T13:25:30Z
updated_at: 2026-06-02T13:28:00Z
parent: AlaskaRouter-xtua
---

Someone cloning the repo needs to know how to build the app and (separately) how to regenerate the bundled data. Write a single orientation doc + wire it in.

- [x] docs/DATA-PIPELINE.md written: artifact table (DB committed / pack fetched), build-and-run happy path with explicit no-.env-to-run callout, places-DB regeneration runbook (prereqs, RIDB key/.env, OSM PBF, run.sh, verify+swap, 8-source table), tile-pack pointer, troubleshooting.
- [x] README: Stack line -> ~34k/8 sources + link; Build & run notes the DB is committed (no key to run); new Regenerating-bundled-data subsection links docs + both tool READMEs.
- [x] tools/build-places/README.md: Prerequisites block (brew osmium-tool/sqlite3, python3 stdlib-only/no requirements.txt) + link to docs/DATA-PIPELINE.md.

## Summary of Changes

Layered docs so a cloner can self-serve: docs/DATA-PIPELINE.md (orientation + runbooks), top-level README wired to it (stale 12k->34k fixed), tools/build-places/README.md gains a Prerequisites block. Key message up front: the search DB is committed, so no API key / Python / .env is needed just to build & run; those are only for regenerating data. All cross-doc relative links verified.
