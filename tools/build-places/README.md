# Places-DB tooling (AlaskaRouter-22h7)

The bundled places database `AlaskaRouter/Resources/alaska-places.sqlite` is
the back end for the in-app search (FTS5 over `name`, `alt_names`, `category`,
`region`). It's small enough (~9 MB) to ship in-bundle, so unlike the tile
pack it doesn't need a GitHub-Releases fetch dance.

The pipeline merges **eight** sources into one deduped gazetteer. The three
"core" sources cover the whole name space; the five "campground/POI" sources
(under `sources/`, added in AlaskaRouter-ief3) add campgrounds, public-use
cabins, trailheads, boat launches, and other recreation POIs with booking and
contact info.

| Script                  | Role                                                                  |
|-------------------------|-----------------------------------------------------------------------|
| `run.sh`                | One-shot rebuild — orchestrates every step below, then `qa_report.py`.|
| `filter_tags.sh`        | `osmium tags-filter` over the raw Alaska OSM PBF.                     |
| `fetch_gnis.sh`         | Downloads the USGS GNIS Alaska state file (idempotent).              |
| `fetch_wikidata.py`     | SPARQL fetch of all Alaska items with coords from WDQS (idempotent). |
| `sources/fetch_ridb.py` | Federal Recreation.gov facilities via RIDB API (needs `RIDB_API_KEY`).|
| `sources/fetch_arcgis.py`| Keyless ArcGIS harvester: BLM AK, DNR state parks, Kenai Borough.    |
| `sources/scrape_acoa.py`| ACOA private-campground directory (robots-checked) + geocoding.      |
| `sources/build` helpers | `common.py` (record contract), `arcgis_layers.py` (layer registry),  |
|                         | `geocode.py` (cached Nominatim), `qa_report.py` (post-build report). |
| `build_fts5.py`         | Reads all sources, dedupes (source-priority + field backfill), writes SQLite. |

### API key (RIDB)

`sources/fetch_ridb.py` needs a free Recreation.gov API key. Get one at
<https://ridb.recreation.gov/> → sign in → Profile → **API Key**, then:

```bash
cp tools/build-places/.env.example tools/build-places/.env
# edit .env, set RIDB_API_KEY=<your-key>
```

`.env` is gitignored and auto-sourced by the fetchers; never commit it. The
key can also come straight from the environment (`export RIDB_API_KEY=…`).

## Prerequisites

```bash
brew install osmium-tool sqlite3     # CLI tools the pipeline shells out to
python3 --version                    # 3.10+ ; standard library only — no pip install
```

The Python scripts depend only on the stdlib (`urllib`, `json`, `sqlite3`, `re`,
`unicodedata`) — there is no `requirements.txt`. RIDB needs a free API key in
`.env` (see above); all other sources are keyless. The raw OSM extract is a
manual one-time download (see "Sources"). A new clone only needs this if it's
*regenerating* the DB — the built `alaska-places.sqlite` is committed.

See [`../../docs/DATA-PIPELINE.md`](../../docs/DATA-PIPELINE.md) for the
end-to-end orientation (both the search DB and the tile pack).

## Quick reference

```bash
# Rebuild the places DB from scratch (assumes data/alaska-latest.osm.pbf
# is already in place — see "Sources" below):
tools/build-places/run.sh

# Then, when satisfied, swap the result into the app bundle:
cp tools/build-places/data/pois.sqlite \
   AlaskaRouter/Resources/alaska-places.sqlite
```

The intermediate ~500 MB of GeoJSON / PBF / GNIS files live under
`tools/build-places/data/` (gitignored). The final `pois.sqlite` is also
written there; the copy to `AlaskaRouter/Resources/` is manual so we can
diff and probe the new DB before swapping it in.

## Sources

The DB is built from eight sources, merged with a two-pass dedup
(`name.lower` + lat/lon rounded to ~150 m, then a 5 km same-name spatial
cluster). The cluster winner is chosen by **importance, then source priority**
(`SOURCE_RANK` in `build_fts5.py`: federal RIDB > state/local GIS > OSM > GNIS
> Wikidata > private ACOA), and the winner's **empty contact fields are
backfilled** from collapsed duplicates while every source's name folds into
`alt_names` — so authoritative booking data and search recall both survive a
merge. Cross-source collisions are uncommon (the new sources mostly *add*
distinct cabins/campgrounds), so backfill is a safety net, not the main event.

> Shared-URL / shared-external-ID dedup (from the original plan) was evaluated
> and skipped: these providers don't share URLs or IDs across each other, so
> name+proximity already catches the real duplicates.

**1. OSM (OpenStreetMap)** — `tools/build-places/data/alaska-latest.osm.pbf`
Strong on businesses, infrastructure, settlements, named landmarks. Filter
in `filter_tags.sh` whitelists ~80 tag values across `amenity`, `tourism`,
`shop`, `natural`, `place`, `leisure`, `boundary`, `craft`, `office`, etc.
Get the latest extract from [Geofabrik Alaska](https://download.geofabrik.de/north-america/us/alaska.html):

```bash
curl -fSL -o tools/build-places/data/alaska-latest.osm.pbf \
  https://download.geofabrik.de/north-america/us/alaska-latest.osm.pbf
```

**2. USGS GNIS** (Geographic Names Information System) — `tools/build-places/data/DomesticNames_AK.txt`
US-government authoritative geographic names. Public domain. Strong on the
long tail of natural features (peaks, lakes, glaciers, capes, bays, islands)
that OSM doesn't always tag. `fetch_gnis.sh` pulls the per-state file from
USGS's S3 bucket and unzips it. The Stream class (~9 k Alaska creeks) is
deliberately skipped to keep DB size sane.

**3. Wikidata** — `tools/build-places/data/wikidata-ak.jsonl`
21 k items located in Alaska with coordinates. Fills culturally and
historically named places that neither OSM nor GNIS surface: indigenous
communities (Savoonga, Hydaburg, Adak, Holy Cross), named landmarks
(Sitka Historical Museum, Iditarod Trail Sled Dog Museum, Mount Juneau,
Aleutian Islands Wilderness), multilingual entries. `fetch_wikidata.py`
issues a single SPARQL query against the Wikidata Query Service (WDQS) —
raw rows (no `GROUP_CONCAT`/`SAMPLE`) so it finishes inside WDQS's 60 s
hard limit; dedupe-by-qid happens in Python. Retries on HTTP 429 with
backoff per WDQS etiquette.

### Campground / POI sources (`sources/`)

Each writes a normalized `data/source-<name>.jsonl` (the `SourceRecord`
contract in `sources/common.py`); `build_fts5.py` ingests the
`data/source-*.jsonl` glob. All fetchers are idempotent (skip when their
output exists; `--force` to refetch) and fail **loud** on a missing key,
unreachable endpoint, or robots-disallow. Approximate AK yields in parens.

**4. RIDB / Recreation.gov** (`source-ridb.jsonl`, ~262) — `sources/fetch_ridb.py`.
The official federal API (Forest Service, NPS, BLM, Corps of Engineers). Pulls
`/facilities?state=AK` with `sort=Name` (offset paging is **unstable without a
sort** — an unsorted pass returns dupes and silently drops rows). Campgrounds
and public-use cabins (the bulk), plus visitor centers / trailheads / picnic
sites; permits and tours are dropped. `Reservable` → `booking_method=online_portal`
with a `recreation.gov/camping/campgrounds/{id}` deep-link. Needs `RIDB_API_KEY`.

**5. BLM Alaska Recreation** (`source-blm_ak.jsonl`, ~201) — `sources/fetch_arcgis.py`.
Keyless ArcGIS FeatureServer (`gis.blm.gov/akarcgis`). 17 layers: campgrounds,
primitive campsites, reservable/free cabins, boat launches, trailheads,
overlooks, interpretive sites, visitor centers, + recreation-area polygons.

**6. Alaska DNR State Parks** (`source-ak_dnr_parks.jsonl`, ~244) — `sources/fetch_arcgis.py`.
Keyless ArcGIS (`arcgis.dnr.alaska.gov/.../DPOR/Park_Boundary_Facility`). The
facility points are public-use Cabins/Huts (with `dnr.alaska.gov` pages); the
boundary polygons (157) become `park` rows at their centroid. *(Note: that
facility layer has no state-park campgrounds — those come from KPB/OSM/RIDB.)*

**7. Kenai Peninsula Borough campgrounds** (`source-kpb.jsonl`, ~83) — `sources/fetch_arcgis.py`.
Keyless AGOL feature service (`services.arcgis.com/ba4DH9pIcqkXJVfl/.../KPB_Campgrounds_view`).
83 borough campground points with a `LINK`.

Endpoints live in `sources/arcgis_layers.py` (`LAYERS`); add a `LayerSpec` to
harvest another ArcGIS layer.

**8. ACOA private campgrounds** (`source-acoa.jsonl`, ~32) — `sources/scrape_acoa.py`.
The Alaska Campground Owners Association member directory (`akcampgrounds.com`),
the one source of private/commercial RV parks. Read via the site's public
`wp-json` REST API; names+addresses parsed, then **geocoded** (cached Nominatim,
`sources/geocode.py`) — so coordinates are approximate. **Robots/ToS:**
`robots.txt` allows `User-agent:* / Allow:/` with `Content-Signal: search=yes,
ai-train=no`; building a local search index is the permitted "search" use and
we don't train models — the scraper re-checks `robots.txt` at runtime and
refuses if that ever changes. Other private directories (Alaska Family
Motorhomes, ACVB, Alaska.org) and the paid AllStays/Campendium scrapers are
**not** used (scope + no paid subscriptions).

## Output schema (v5)

```sql
place_meta (
  rowid, osm_type, osm_id, lat, lon,
  category, importance, name, alt_names,
  source,                                 -- 'osm'|'gnis'|'wikidata'|'ridb'|
                                          --   'blm_ak'|'ak_dnr_parks'|'kpb'|'acoa'
  admin_area,                             -- borough/census area (v4)
  phone, website, booking_method,         -- v5 campground/POI enrichment;
  open_season, source_url                 --   '' when unknown
);
places_word USING fts5(name, alt_names, category, region,
                       tokenize='unicode61 remove_diacritics 2',
                       prefix='2 3 4 5');
metadata (key, value);                    -- schema_version, built_at,
                                          -- per-source counts + MD5s.
```

`booking_method` ∈ `online_portal | phone_email | walk_in | no_reservations |
unknown | ''`. The legacy `osm_type`/`osm_id` columns hold the source's native
id (GNIS feature_id, Wikidata Q-number, or a stable hash for the new sources);
the `source` column is the canonical signal — read that. The v5 columns are
**additive** — the app reads `place_meta` by named columns and has no
`schema_version` gate, so older app builds keep working against a v5 DB.

## Xcode integration

The build phase has no fetch step (unlike the tile pack — the DB is
small enough to commit). Drop a new `alaska-places.sqlite` into
`AlaskaRouter/Resources/` and Xcode picks it up on the next build.
