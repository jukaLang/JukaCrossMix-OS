#!/bin/sh
# Off-device checks for the RetroArch binary picker in Apps/RetroArch/launch.sh.
# The script uses absolute device paths, so a copy of it is remapped into a
# temporary tree and button_state.sh / ra_audio_switcher.sh / selector are
# stubbed.  What the stub "selected" is the binary the launcher must run.
#
#   sh tests/retroarch_launcher_test.sh [path/to/launch.sh]
#
# The optional argument lets the same checks be pointed at another revision of
# the script (e.g. one taken from git) to confirm they still catch the bug.
#
# Exit status 0 = all checks passed, 1 = at least one failed.

REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC=${1:-"$REPO/Apps/RetroArch/launch.sh"}

T=${TMPDIR:-/tmp}/retroarch_launcher_test
FAILED=0
CHECKS=0

pass() {
    CHECKS=$((CHECKS + 1))
    printf 'ok   - %s\n' "$1"
}
fail() {
    CHECKS=$((CHECKS + 1))
    FAILED=$((FAILED + 1))
    printf 'FAIL - %s\n' "$1"
}
check_eq() { # label expected actual
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected [$2], got [$3])"; fi
}
check_grep() { # label pattern file
    if grep -q -F -- "$2" "$3" 2>/dev/null; then pass "$1"; else fail "$1 (missing [$2])"; fi
}
check_no_grep() { # label pattern file
    if grep -q -F -- "$2" "$3" 2>/dev/null; then fail "$1 (unexpected [$2])"; else pass "$1"; fi
}
check_no_grep_exists() { # label pattern path-that-must-not-exist
    if [ -e "$3" ] && grep -q -F -- "$2" "$3" 2>/dev/null; then
        fail "$1 (unexpected [$2])"
    else
        pass "$1"
    fi
}

# --------------------------------------------------------------------- setup
# setup <device> <binary>...
setup() {
    device=$1
    shift

    rm -rf "$T"
    mkdir -p "$T/sdcard/RetroArch" "$T/sdcard/System/bin" \
        "$T/sdcard/System/usr/trimui/scripts" "$T/etc" "$T/var/trimui_inputd"

    # Remap the device paths into the temp tree, keeping the file name.
    sed -e "s|/mnt/SDCARD|$T/sdcard|g" \
        -e "s|/etc/trimui_device.txt|$T/etc/trimui_device.txt|g" \
        -e "s|/var/trimui_inputd|$T/var/trimui_inputd|g" \
        "$SRC" >"$T/sdcard/Apps_launch.sh"
    chmod +x "$T/sdcard/Apps_launch.sh"

    printf '%s\n' "$device" >"$T/etc/trimui_device.txt"

    for name in "$@"; do
        printf '#!/bin/sh\necho "ran %s" >>"%s"\n' "$name" "$T/ran.log" \
            >"$T/sdcard/RetroArch/$name"
        chmod +x "$T/sdcard/RetroArch/$name"
    done

    # The picker is reached only when the Y button reports "10".
    {
        printf '#!/bin/sh\n'
        printf 'exit 10\n'
    } >"$T/sdcard/System/usr/trimui/scripts/button_state.sh"

    printf '#!/bin/sh\nexit 0\n' >"$T/sdcard/System/usr/trimui/scripts/ra_audio_switcher.sh"
    chmod +x "$T/sdcard/System/usr/trimui/scripts/button_state.sh" \
        "$T/sdcard/System/usr/trimui/scripts/ra_audio_switcher.sh"

    # Stub selector: records every argument, then "selects" the first filename.
    cat >"$T/sdcard/System/bin/selector" <<'STUB'
#!/bin/sh
: >"$JUKAMIX_TEST_SELECTOR_ARGS"
chosen=""
for arg in "$@"; do
    printf '%s\n' "$arg" >>"$JUKAMIX_TEST_SELECTOR_ARGS"
    case "$arg" in
    -*) ;;
    *) chosen=$arg ;; # the choice list comes last, so this is a file name
    esac
done
printf 'You selected: %s\n' "$chosen"
STUB
    chmod +x "$T/sdcard/System/bin/selector"

    launcher="$T/sdcard/Apps_launch.sh"
    args="$T/selector.args"
    : >"$T/ran.log"
    : >"$args"
    export JUKAMIX_TEST_SELECTOR_ARGS="$args"

    sh "$launcher" >"$T/out.txt" 2>&1
}

wrap() { # file -> one line with the argument separator made visible
    awk '{printf "%s|", $0}' "$1"
}

# ------------------------------------- 1. two binaries for the current device
printf '\n== two binaries for the current device ==\n'
setup tsp ra64.trimui_tsp_1.20.0.bin ra64.trimui_tsp_1.21.0.bin
check_eq "the choice list is -c plus one argument per binary" \
    '-fs|120|-c|ra64.trimui_tsp_1.20.0.bin|ra64.trimui_tsp_1.21.0.bin|' \
    "$(wrap "$args")"
check_no_grep "no --file argument is passed" "--file" "$args"
check_grep "the selected binary is launched" "ran ra64.trimui_tsp_1.21.0.bin" "$T/ran.log"

# ------------------------------- 2. the Brick fallback on a Brick Pro device
printf '\n== Brick binaries on a Brick Pro device ==\n'
setup brickpro ra64.trimui_brick_1.21.0.bin
check_eq "Brick binaries are offered" \
    '-fs|120|-c|ra64.trimui_brick_1.21.0.bin|' \
    "$(wrap "$args")"
check_grep "the Brick binary is launched" "ran ra64.trimui_brick_1.21.0.bin" "$T/ran.log"

# ------------------------------------------- 3. a name that contains a space
printf '\n== a binary whose name contains a space ==\n'
setup tsp "ra64.trimui_tsp_odd name.bin"
check_eq "a spaced name stays a single argument" \
    '-fs|120|-c|ra64.trimui_tsp_odd name.bin|' \
    "$(wrap "$args")"
check_grep "the spaced binary is launched" "ran ra64.trimui_tsp_odd name.bin" "$T/ran.log"

# ------------------------------------ 4. no binary at all for this device
printf '\n== no binary for the device ==\n'
setup tsp
check_grep "the user is told no binary was found" "No files found for device tsp." "$T/out.txt"
check_eq "the selector is not opened with a glob" "" "$(cat "$args")"
check_no_grep_exists "nothing is launched" "ran " "$T/ran.log"

# ------------------------------------------------------------------- summary
printf '\n%d checks, %d failed\n' "$CHECKS" "$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
exit 0
