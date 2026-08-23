#!/usr/bin/env bash
#
# Fetch the compressed RetroArch cores archive at build time.
#
# The archive (~335 MB, 165 cores) is too large for git, so it lives in the
# jukaLang/Packages repository ("cores" release) and is pulled here by the
# release workflow. This script is host-side build tooling and never ships
# on the SD card.
#
# Usage: bash scripts/fetch_cores.sh
set -u

CORE_DIR="RetroArch/.retroarch/cores"
OUT_FILE="$CORE_DIR/cores.7z"

mkdir -p "$CORE_DIR"

if [ -f "$OUT_FILE" ]; then
    echo "cores.7z already present: $(du -h "$OUT_FILE" | cut -f1)"
    exit 0
fi

if ls "$CORE_DIR"/*.so >/dev/null 2>&1; then
    echo "RetroArch cores already present in the image (skipping fetch)"
    exit 0
fi

# Resolve the asset URL via the GitHub API so we don't hardcode the filename.
URL=$(curl -fsSL "https://api.github.com/repos/jukaLang/Packages/releases/tags/cores" |
    python3 -c 'import json, sys; d = json.load(sys.stdin); print(next(a["browser_download_url"] for a in d.get("assets", []) if a["name"].endswith(".7z")))' 2>/dev/null)

if [ -z "${URL:-}" ]; then
    echo "::error::Could not resolve the cores release URL from jukaLang/Packages" >&2
    exit 1
fi

echo "Downloading cores archive from: $URL"
curl -fL --retry 3 -o "$OUT_FILE" "$URL" || {
    echo "::error::cores.7z download failed" >&2
    rm -f "$OUT_FILE"
    exit 1
}

echo "cores.7z downloaded: $(du -h "$OUT_FILE" | cut -f1)"
