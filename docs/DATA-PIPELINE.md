# Data pipeline — bundled data, building, and regenerating

AlaskaRouter is **offline-first**, so its geographic data ships *with the app*
rather than being fetched at runtime. There are exactly **two** bundled data
artifacts, and they're handled differently:

| Artifact | File | In git? | A cloner must… |
|---|---|---|---|
| **Places search DB** | `AlaskaRouter/Resources/alaska-places.sqlite` (~9 MB) | ✅ **committed** | nothing — it's already there |
| **Offline tile pack** | `AlaskaRouter/Resources/alaska-pack.pmtiles` (~447 MB) | ❌ gitignored | run `tools/build-pack/fetch-pack.sh` once |

> **TL;DR for "I just want to build and run":** the search DB is committed, so
> the only data step is fetching the tile pack. You do **not** need an API key,
> Python, `osmium`, or a `.env` file to build and run the app — those are only
> for *regenerating* the search DB. See [Build & run](#1-build--run-the-app).

This doc is the orientation map. The two deep runbooks live next to their tools:
- **Places DB:** [`tools/build-places/README.md`](../tools/build-places/README.md)
- **Tile pack:** [`tools/build-pack/README.md`](../tools/build-pack/README.md)

---

## 1. Build & run the app

The happy path (see also the top-level [README](../README.md#build--run)):

```bash
brew install xcodegen gh jq pmtiles     # one-time toolchain
git clone git@github.com:limar/AlaskaRouter.git
cd AlaskaRouter

tools/build-pack/fetch-pack.sh          # fetch the 447 MB tile pack (required)
xcodegen generate                       # generate the .xcodeproj
open AlaskaRouter.xcodeproj             # then ⌘R
```

The search DB is already in `AlaskaRouter/Resources/` (committed), so search
works immediately. `fetch-pack.sh` is idempotent (SHA-256 verified, skips if the
local pack matches). That's the entire data setup for running the app.

---

## 2. Regenerate the **places search DB**

This is a **maintainer task** — only needed when refreshing the data (new OSM
extract, new campground/POI source, schema change). The app already ships a
built DB, so you can skip this unless you're updating the data.

The DB is a unified offline gazetteer (FTS5) built by merging **eight** sources.
Full details — every endpoint, the dedup/source-priority logic, the schema — are
in [`tools/build-places/README.md`](../tools/build-places/README.md). The
practical runbook:

### 2.1 Prerequisites

```bash
brew install osmium-tool sqlite3        # CLI tools the pipeline shells out to
python3 --version                       # 3.10+ ; STDLIB ONLY — no pip install needed
```

The Python scripts use only the standard library (`urllib`, `json`, `sqlite3`,
`re`, `unicodedata`). There is intentionally **no `requirements.txt`**.

### 2.2 One-time: API key (`.env`)

Exactly one source needs a key: **RIDB / Recreation.gov** (federal campgrounds &
cabins). It's free.

1. Get a key: <https://ridb.recreation.gov/> → sign in → **Profile** → **API Key**
   (a UUID; no cost, no approval wait).
2. Create the gitignored env file:
   ```bash
   cp tools/build-places/.env.example tools/build-places/.env
   # edit it: RIDB_API_KEY=<your-key>
   ```

`tools/build-places/.env` is **gitignored** and auto-sourced by the fetchers —
never commit it. (You can also just `export RIDB_API_KEY=…` instead of the file.)
The other seven sources are keyless. If the key is missing, only the RIDB step
fails (loudly, with this same instruction); everything else still builds.

### 2.3 One-time: download the OSM extract

The OSM base layer is a ~140 MB Geofabrik extract (not in git, regenerable):

```bash
curl -fSL -o tools/build-places/data/alaska-latest.osm.pbf \
  https://download.geofabrik.de/north-america/us/alaska-latest.osm.pbf
```

(GNIS, Wikidata, RIDB, the ArcGIS layers, and the ACOA directory are all fetched
automatically by the pipeline — no manual download.)

### 2.4 Run the pipeline

```bash
tools/build-places/run.sh
```

This runs, in order: OSM tag-filter → GNIS → Wikidata → RIDB → ArcGIS (BLM /
DNR / Kenai Borough) → ACOA scrape+geocode → merge/dedup/build → QA report.
Every fetch step is **idempotent** (skips when its `data/source-*.jsonl` already
exists; pass `--force` to a single fetcher to refetch). Expect a few minutes,
dominated by the OSM GeoJSON export and the polite (1 req/s) ACOA geocoding.

Output: `tools/build-places/data/pois.sqlite` plus a QA summary. Everything
under `data/` is gitignored scratch.

### 2.5 Verify, then swap into the app

The copy into the bundle is **manual on purpose**, so you can diff/probe first:

```bash
python3 tools/build-places/sources/qa_report.py    # per-source + coverage report
# happy? promote it:
cp tools/build-places/data/pois.sqlite \
   AlaskaRouter/Resources/alaska-places.sqlite
```

Then rebuild the app. The schema is additive and the app reads named columns
(no schema-version gate), so a newer DB is backward-compatible with older app
builds. Commit the updated `.sqlite` (it's small enough to live in git).

### 2.6 What the eight sources are (one-liner each)

| Source | Adds | Key? |
|---|---|---|
| OpenStreetMap | businesses, settlements, landmarks, + contact/booking tags | no |
| USGS GNIS | long-tail natural-feature names (peaks, lakes, glaciers) | no |
| Wikidata | cultural/historic/indigenous names | no |
| RIDB / Recreation.gov | federal campgrounds + public-use cabins, booking links | **yes** |
| BLM Alaska Recreation | campgrounds, cabins, boat launches, trailheads (ArcGIS) | no |
| Alaska DNR State Parks | state-park cabins/huts + park boundaries (ArcGIS) | no |
| Kenai Peninsula Borough | borough campgrounds (ArcGIS) | no |
| ACOA | private/commercial RV parks (robots-checked scrape + geocode) | no |

Adding another source = write one fetcher that emits a `SourceRecord`
(`tools/build-places/sources/common.py`) to `data/source-<name>.jsonl`; the
build globs it in automatically. For another ArcGIS layer, just add a
`LayerSpec` to `sources/arcgis_layers.py`. See the deep README for the contract.

---

## 3. Regenerate the **tile pack**

Usually you just fetch it (§1). To rebuild from scratch (≈2 h, polite scraping
of OpenTopoMap) or publish a new release, see
[`tools/build-pack/README.md`](../tools/build-pack/README.md). In brief:

```bash
tools/build-pack/fetch-pack.sh          # download the current release asset
tools/build-pack/download_tiles.py      # OR rebuild from OpenTopoMap (~2 h)
tools/build-pack/release-pack.sh        # publish a new pack release
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| App builds but the map is blank | Tile pack missing — run `tools/build-pack/fetch-pack.sh`. |
| `fetch_ridb.py` exits "env var RIDB_API_KEY is not set" | Create `tools/build-places/.env` with your key (§2.2). |
| `osmium: command not found` | `brew install osmium-tool`. |
| `run.sh` stops at `filter_tags.sh` | The OSM PBF isn't downloaded — see §2.3. |
| A fetcher prints "already present (… records)" | That's the idempotent skip; pass `--force` to refetch. |
| ACOA scrape refuses to run | It re-checks `robots.txt` at runtime and stops if `*` is disallowed — expected, not a bug. |
| Want to start a source over | Delete its `tools/build-places/data/source-<name>.jsonl` (and `geocode-cache.json` for ACOA) and re-run. |
