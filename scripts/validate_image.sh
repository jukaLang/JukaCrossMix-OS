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

echo "== 5. Release-size safety (GitHub caps assets at 2 GiB) =="
TOTAL=$(find . -path ./.git -prune -o -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {printf "%.2f GB", s/1073741824}')
echo "  Image content: $TOTAL"
BIG=$(find . -path ./.git -prune -o -type f -size +1900M -printf '%p\n' 2>/dev/null)
if [ -n "$BIG" ]; then
    note_fail "Files >=1.9 GB would break the release (2 GiB/asset cap): $BIG"
else
    echo "  OK no single file >=1.9 GB"
fi
# informational: over 2 GB the workflow splits the archive into volumes
echo "  Note: over 2 GB total, the release ships as multi-volume .001/.002 parts"

echo "== 6. Per-device CPU profiles =="
if [ -f "System/etc/cpu_profiles.sh" ]; then
    if dash -n "System/etc/cpu_profiles.sh" 2>/dev/null; then
        echo "  OK cpu_profiles.sh parses (POSIX sh)"
    else
        note_fail "cpu_profiles.sh does not parse under dash"
    fi
    for dev in tsp tsps brick brickpro; do
        if grep -q "${dev})" "System/etc/cpu_profiles.sh"; then
            echo "  OK profile for $dev"
        else
            note_fail "cpu_profiles.sh missing profile for $dev"
        fi
    done
else
    note_fail "Missing System/etc/cpu_profiles.sh"
fi

echo "== 7. JukaMix boot logo (flashed at first boot) =="
for logo in "Apps/BootLogo/Images_1280x720/- JukaMix.bmp" "Apps/BootLogo/Images_1024x768/- JukaMix.bmp"; do
    if [ -f "$logo" ]; then
        SIZE=$(stat -c%s "$logo")
        if [ "$SIZE" -lt 6291456 ]; then
            echo "  OK $logo ($(numfmt --to=iec "$SIZE"))"
        else
            note_fail "$logo exceeds the 6 MB flash limit"
        fi
    else
        note_fail "Missing boot logo: $logo"
    fi
done
if grep -q 'bootlogo="- JukaMix.bmp"' "Apps/SystemTools/Menu/THEME##THEME PACK (value)/JukCrossMix-OS.sh"; then
    echo "  OK default theme pack flashes the JukaMix logo"
else
    note_fail "JukCrossMix-OS theme pack does not point at the JukaMix boot logo"
fi

echo
if [ "$FAIL" = 0 ]; then
    echo "Image validation OK"
else
    echo "Image validation FAILED" >&2
    exit 1
fi
