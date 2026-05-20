#!/usr/bin/env bash
# AlaskaRouter-76y3 — Publish the local alaska-pack.pmtiles as a GitHub Release.
#
# Builds a SHA-256 sidecar for each asset so fetch-pack.sh can verify and
# skip re-downloads. The release tag uses the manifest's `version` field
# (typically a date, e.g. data/alaska-2026-05-19). The release title and
# notes are derived from the same manifest so the asset stays self-describing.
#
# Usage:
#   tools/build-pack/release-pack.sh                   # tag = manifest.version
#   tools/build-pack/release-pack.sh -t data/foo       # explicit tag
#
# Requires: gh CLI (Homebrew: brew install gh), jq, shasum (built-in).

set -euo pipefail

REPO="${ALASKA_ROUTER_REPO:-limar/AlaskaRouter}"
RESOURCES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/AlaskaRouter/Resources"
PMTILES="${RESOURCES}/alaska-pack.pmtiles"
MANIFEST="${RESOURCES}/alaska-pack.manifest.json"

[[ -f "${PMTILES}" ]] || { echo "❌ ${PMTILES} not found" >&2; exit 1; }
[[ -f "${MANIFEST}" ]] || { echo "❌ ${MANIFEST} not found" >&2; exit 1; }

TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--tag) TAG="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ -z "${TAG}" ]]; then
  VERSION="$(jq -r '.version' "${MANIFEST}")"
  TAG="data/alaska-${VERSION}"
fi

TITLE="$(jq -r '.title' "${MANIFEST}") — ${TAG##*/}"
SIZE_MB="$(( $(stat -f %z "${PMTILES}") / 1024 / 1024 ))"
TOTAL_TILES="$(jq -r '.total_tile_count // "?"' "${MANIFEST}")"

NOTES="$(cat <<EOF
$(jq -r '.description' "${MANIFEST}")

- ${SIZE_MB} MB after PMTiles dedup
- ${TOTAL_TILES} tiles covering $(jq -r '.coverage | map(.name) | join(" + ")' "${MANIFEST}")
- Source: OpenTopoMap (CC-BY-SA), © OpenStreetMap contributors

Regenerate from scratch with \`tools/build-pack/download_tiles.py\` + \`pmtiles convert\`.
EOF
)"

# SHA sidecars for fetch-pack.sh's verify-on-download.
( cd "${RESOURCES}" && shasum -a 256 alaska-pack.pmtiles > alaska-pack.pmtiles.sha256 )
( cd "${RESOURCES}" && shasum -a 256 alaska-pack.manifest.json > alaska-pack.manifest.json.sha256 )

echo "Creating release ${TAG} on ${REPO}..."
gh release create "${TAG}" \
  --repo "${REPO}" \
  --title "${TITLE}" \
  --notes "${NOTES}" \
  "${PMTILES}" \
  "${PMTILES}.sha256" \
  "${MANIFEST}" \
  "${MANIFEST}.sha256"

echo "Done. Verify with: tools/build-pack/fetch-pack.sh ${TAG}"
