# Places-DB tooling (AlaskaRouter-22h7)

The bundled places database `AlaskaRouter/Resources/alaska-places.sqlite` is
the back end for the in-app search (FTS5 over `name`, `alt_names`, `category`,
`region`). It's small enough (~8 MB) to ship in-bundle, so unlike the tile
pack it doesn't need a GitHub-Releases fetch dance. Four scripts in this
directory cover the rebuild lifecycle:

| Script              | Role                                                              |
|---------------------|-------------------------------------------------------------------|
| `run.sh`            | One-shot rebuild — orchestrates the four steps below.             |
| `filter_tags.sh`    | `osmium tags-filter` over the raw Alaska OSM PBF.                 |
| `fetch_gnis.sh`     | Downloads the USGS GNIS Alaska state file (idempotent).           |
| `fetch_wikidata.py` | SPARQL fetch of all Alaska items with coords from WDQS (idempotent). |
| `build_fts5.py`     | Reads OSM GeoJSON + GNIS + Wikidata, dedupes, writes the SQLite.  |

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

The DB is built from three complementary sources, merged with a coord-key
dedup (`name.lower` + lat/lon rounded to ~150 m). OSM wins ties so its
richer tagging (`alt_names`, sub-categorization) survives; GNIS and
Wikidata fill the long tail.

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

## Output schema (v3)

```sql
place_meta (
  rowid, osm_type, osm_id, lat, lon,
  category, importance, name, alt_names,
  source                                  -- 'osm' | 'gnis' | 'wikidata'
);
places_word USING fts5(name, alt_names, category, region,
                       tokenize='unicode61 remove_diacritics 2',
                       prefix='2 3 4 5');
metadata (key, value);                    -- schema_version, built_at,
                                          -- per-source counts + MD5s.
```

The legacy `osm_type`/`osm_id` columns hold `'gnis'`/GNIS feature_id for
GNIS rows and `'wikidata'`/Q-id integer for Wikidata rows. The `source`
column is the canonical signal — read that.

## Xcode integration

The build phase has no fetch step (unlike the tile pack — the DB is
small enough to commit). Drop a new `alaska-places.sqlite` into
`AlaskaRouter/Resources/` and Xcode picks it up on the next build.
