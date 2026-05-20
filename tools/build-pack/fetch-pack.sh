#!/usr/bin/env bash
# AlaskaRouter-76y3 — Fetch the bundled tile pack from a GitHub Release.
#
# Tile pack (~447 MB) is too large for GitHub's per-file limit and is hosted
# as a release asset. This script downloads the named release's pmtiles +
# manifest into AlaskaRouter/Resources/ so Xcode can pick them up at build
# time. Idempotent — skips download if the local SHA-256 matches.
#
# Usage:
#   tools/build-pack/fetch-pack.sh                  # latest data-* tag
#   tools/build-pack/fetch-pack.sh data/alaska-...  # specific tag
#
# Requires: curl, jq (Homebrew has both). For full regeneration from
# OpenTopoMap instead, see tools/build-pack/download_tiles.py.

set -euo pipefail

REPO="${ALASKA_ROUTER_REPO:-limar/AlaskaRouter}"
TAG="${1:-}"
RESOURCES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/AlaskaRouter/Resources"
PMTILES="${RESOURCES}/alaska-pack.pmtiles"
MANIFEST="${RESOURCES}/alaska-pack.manifest.json"

mkdir -p "${RESOURCES}"

# Resolve tag: if none specified, find the most recent tag starting with "data/".
if [[ -z "${TAG}" ]]; then
  echo "Resolving latest data/* release from ${REPO}..."
  TAG="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases" \
    | jq -r '.[] | select(.tag_name | startswith("data/")) | .tag_name' \
    | head -1 || true)"
  if [[ -z "${TAG}" ]]; then
    echo "❌ No data/* release found on ${REPO}." >&2
    echo "   Create one with: tools/build-pack/release-pack.sh" >&2
    exit 1
  fi
fi
echo "Using release: ${TAG}"

ASSET_BASE="https://github.com/${REPO}/releases/download/${TAG}"

fetch_if_changed() {
  local url="$1" dest="$2"
  local expected_sha=""

  # Try to read the corresponding .sha256 sidecar from the release.
  if expected_sha="$(curl -fsSL "${url}.sha256" 2>/dev/null | awk '{print $1}')"; then
    if [[ -f "${dest}" ]]; then
      local local_sha
      local_sha="$(shasum -a 256 "${dest}" | awk '{print $1}')"
      if [[ "${local_sha}" == "${expected_sha}" ]]; then
        echo "  ✓ ${dest##*/} already up-to-date"
        return 0
      fi
    fi
  fi

  echo "  ↓ ${url} → ${dest}"
  curl -fSL --progress-bar "${url}" -o "${dest}.tmp"
  mv "${dest}.tmp" "${dest}"
  if [[ -n "${expected_sha}" ]]; then
    local got
    got="$(shasum -a 256 "${dest}" | awk '{print $1}')"
    if [[ "${got}" != "${expected_sha}" ]]; then
      echo "❌ SHA mismatch on ${dest}: got ${got}, expected ${expected_sha}" >&2
      exit 1
    fi
  fi
}

fetch_if_changed "${ASSET_BASE}/alaska-pack.pmtiles" "${PMTILES}"
fetch_if_changed "${ASSET_BASE}/alaska-pack.manifest.json" "${MANIFEST}"

echo "Done. Tile pack staged at ${PMTILES}"
