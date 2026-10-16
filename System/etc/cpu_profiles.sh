# Per-device CPU frequency profiles (values in kHz).
#
# The Smart Pro, Brick and Brick Pro use the Allwinner A133P family (4x
# Cortex-A53, up to 1.8 GHz). The Smart Pro S uses the newer Allwinner A523
# (8x Cortex-A55) whose stock kernel also exposes the 2000 MHz step. All of
# them share the same cpufreq ladder
# (408 / 600 / 816 / 1008 / 1200 / 1416 / 1608 / 1800 / 2000 MHz).
#
# CPU_FREQ_MAX is the highest step the running device can actually reach, so
# "max" tools and the OSD frequency sliders never request a step the SoC
# rejects: the A133P stock kernel has no 2000 MHz step and silently ignores
# the write, which used to break Extreme / Max modes. Launchers written for
# the faster A523 that ask for 2000 MHz are clamped to it by cpufreq.sh.
#
#   CPU_FREQ_MAX      : highest frequency the device supports (stock kernel)
#   CPU_FREQ_BOOST_MIN: minimum frequency used in performance/boost mode
#
# This file is sourced by cpufreq.sh, cpu_boost.sh and the Fn-key CPU tools.
# It is pure POSIX sh and ships on the SD card (System/etc).

read -r JUKAMIX_DEVICE </etc/trimui_device.txt 2>/dev/null
JUKAMIX_DEVICE="${JUKAMIX_DEVICE:-unknown}"

case "$JUKAMIX_DEVICE" in
tsp)      CPU_FREQ_MAX=1800000 ; CPU_FREQ_BOOST_MIN=1416000 ;; # TrimUI Smart Pro (A133P)
tsps)     CPU_FREQ_MAX=2000000 ; CPU_FREQ_BOOST_MIN=1416000 ;; # TrimUI Smart Pro S (A523)
brick)    CPU_FREQ_MAX=1800000 ; CPU_FREQ_BOOST_MIN=1416000 ;; # TrimUI Brick (A133P)
brickpro) CPU_FREQ_MAX=1800000 ; CPU_FREQ_BOOST_MIN=1416000 ;; # TrimUI Brick Pro (A133P)
smart)    CPU_FREQ_MAX=1008000 ; CPU_FREQ_BOOST_MIN=816000  ;; # TrimUI Smart (original, low-power SoC)
*)        CPU_FREQ_MAX=1800000 ; CPU_FREQ_BOOST_MIN=1416000 ;; # A133P family fallback
esac

export CPU_FREQ_MAX CPU_FREQ_BOOST_MIN
