# Tile pack tooling (AlaskaRouter-76y3)

The bundled tile pack `AlaskaRouter/Resources/alaska-pack.pmtiles` is **~447 MB**, well above GitHub's 100 MB per-file limit, so it does not live in git. Three scripts in this directory cover the lifecycle:

| Script | When |
|---|---|
| `fetch-pack.sh`     | After a fresh clone (or whenever the pack is missing). Downloads from the latest `data/alaska-*` release. |
| `release-pack.sh`   | When publishing a new pack version. Uploads to a new release tag. |
| `download_tiles.py` | One-shot, resumable tile downloader. Use only when the tile source permits the requested bulk/offline use. |

## Quick reference

```bash
# After cloning the repo:
tools/build-pack/fetch-pack.sh

# Estimate the current v1 target without downloading:
tools/build-pack/download_tiles.py --db tools/build-pack/data/alaska-pack.mbtiles --dry-run

# Publishing a new pack (after rebuilding/converting):
tools/build-pack/release-pack.sh

# Targeting a non-default GitHub repo (e.g. a fork):
ALASKA_ROUTER_REPO=yourname/AlaskaRouter tools/build-pack/fetch-pack.sh
```

`fetch-pack.sh` verifies the SHA-256 sidecar on each download, and skips the fetch when the local file already matches. Re-running it is safe.

## Why a release asset and not LFS?

Tile pack is **derived data**. Git LFS would charge ongoing storage + bandwidth for what's effectively a build artifact. GitHub Releases gives us versioned binary attachments for free, tagged independently of code commits, and the `data/alaska-*` tag pattern keeps them separate from app release tags.

Important: `download_tiles.py` performs bulk prefetching into an offline archive. Do not point it at a volunteer/public tile server unless that service explicitly permits this use or we have contacted the operator and received approval. For larger detail packs, prefer a self-render pipeline from OSM/SRTM source data or a provider/export path intended for offline packages.

## When to cut a new pack release

- Tile coverage expanded (new region or zoom level)
- Basemap source updated (OpenTopoMap restyling, etc.)
- Pack format / schema changed

Bump `version` in `AlaskaRouter/Resources/alaska-pack.manifest.json` to today's date, run `release-pack.sh`, and the tag/title/notes flow automatically.

## Xcode integration

To make a fresh clone produce a working build, add a Run Script build phase **before Compile Sources**:

```bash
if [[ ! -f "${SRCROOT}/AlaskaRouter/Resources/alaska-pack.pmtiles" ]]; then
  "${SRCROOT}/tools/build-pack/fetch-pack.sh"
fi
```

Xcode will idempotently fetch the pack on first build, and skip on subsequent builds.
