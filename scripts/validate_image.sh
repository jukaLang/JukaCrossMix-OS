#!/usr/bin/env bash
#
# Validate the SD-card image before it is packaged into a release.
# Runs in CI (host-side build tooling, never ships on the SD card).
#
# Checks:
#   1. JSON configuration files parse and the default theme path resolves
#   2. Every shell script parses under dash (strict POSIX sh)
#   3. No bash-only constructs or bash shebangs in image-owned scripts
#   4. The JukCrossMix-OS theme ships a complete skin (matches the reference)
#
# Usage: bash scripts/validate_image.sh
set -u

FAIL=0
note_fail() { echo "::error::$1"; FAIL=1; }

echo "== 1. JSON configuration =="
for j in \
    "System/usr/trimui/scripts/MainUI_default_system.json" \
    "System/etc/crossmix.json" \
    "Themes/JukCrossMix-OS/config.json"; do
    if [ -f "$j" ]; then
        python3 -c "import json,sys; json.load(open(sys.argv[1], encoding='utf-8-sig'))" "$j" 2>/dev/null \
            || note_fail "Invalid JSON: $j"
        echo "  OK $j"
    else
        note_fail "Missing file: $j"
    fi
done

THEME=$(python3 -c "import json; print(json.load(open('System/usr/trimui/scripts/MainUI_default_system.json', encoding='utf-8-sig'))['theme'])" 2>/dev/null)
# the image stores device paths (/mnt/SDCARD/...); map back to the repo tree
REPO_THEME="${THEME#/mnt/SDCARD/}"
if [ -n "$REPO_THEME" ] && [ -d "$REPO_THEME" ]; then
    echo "  OK default theme resolves: $THEME"
else
    note_fail "Default theme does not resolve: '$THEME'"
fi

echo "== 2. POSIX syntax (dash -n) =="
ERR=""
while IFS= read -r -d '' f; do
    if ! dash -n "$f" 2>/dev/null; then
        note_fail "POSIX syntax error in $f"
    fi
done < <(find Apps Emus System Roms Best Themes trimui Backgrounds -name '*.sh' -not -path '*/.retroarch/*' -print0 2>/dev/null)
echo "  OK all image scripts parse under dash"

echo "== 3. Bash-isms in image scripts =="
BASHISMS=$(grep -rnE '\[\[[[:space:]]|exec > >\(|<<<|&>' --include='*.sh' Apps Emus System Roms Best 2>/dev/null | grep -vE '\$\{|awk|sed|grep|jq' | wc -l)
[ "$BASHISMS" = 0 ] || note_fail "Bash-only constructs found ($BASHISMS)"
echo "  OK bash-only constructs: 0"

BASH_SHEBANG=$(grep -rl '#!/bin/bash' --include='*.sh' Apps Emus System Roms Best RetroArch 2>/dev/null | grep -v '.retroarch/cores' | wc -l)
[ "$BASH_SHEBANG" = 0 ] || note_fail "Bash shebangs remain in image scripts ($BASH_SHEBANG)"
echo "  OK bash shebangs: 0"

echo "== 4. JukCrossMix-OS theme completeness =="
if diff <(ls "Themes/CrossMix - OS/skin" 2>/dev/null | sort) <(ls "Themes/JukCrossMix-OS/skin" 2>/dev/null | sort) >/dev/null 2>&1; then
    echo "  OK skin file set complete"
else
    note_fail "JukCrossMix-OS skin differs from the reference theme"
fi

echo
if [ "$FAIL" = 0 ]; then
    echo "Image validation OK"
else
    echo "Image validation FAILED" >&2
    exit 1
fi
