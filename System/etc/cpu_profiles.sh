# Per-device CPU frequency profiles (values in kHz).
#
# All current devices (Smart Pro, Smart Pro S, Brick, Brick Pro) use the
# Allwinner A133P family (4x Cortex-A53) and share the same cpufreq steps
# (408 / 600 / 816 / 1008 / 1200 / 1416 / 1608 / 1800 MHz). The 2000 MHz
# step exists only on overclocked kernels, so "max" tools must not request it
# blindly: the cpufreq driver rejects out-of-range writes, which silently
# breaks Extreme / Max modes on stock firmware.
#
#   CPU_FREQ_MAX      : highest frequency the device supports (stock kernel)
#   CPU_FREQ_BOOST_MIN: minimum frequency used in performance/boost mode
#
# This file is sourced by cpufreq.sh, cpu_boost.sh and the Fn-key CPU tools.
# It is pure POSIX sh and ships on the SD card (System/etc).

read -r JUKAMIX_DEVICE </etc/trimui_device.txt 2>/dev/null
JUKAMIX_DEVICE="${JUKAMIX_DEVICE:-unknown}"

case "$JUKAMIX_DEVICE" in
tsp)      CPU_FREQ_MAX=1800000 ; CPU_FREQ_BOOST_MIN=1416000 ;; # TrimUI Smart Pro
tsps)     CPU_FREQ_MAX=1800000 ; CPU_FREQ_BOOST_MIN=1416000 ;; # TrimUI Smart Pro S
brick)    CPU_FREQ_MAX=1800000 ; CPU_FREQ_BOOST_MIN=1416000 ;; # TrimUI Brick
brickpro) CPU_FREQ_MAX=1800000 ; CPU_FREQ_BOOST_MIN=1416000 ;; # TrimUI Brick Pro
smart)    CPU_FREQ_MAX=1008000 ; CPU_FREQ_BOOST_MIN=816000  ;; # TrimUI Smart (original, low-power SoC)
*)        CPU_FREQ_MAX=1800000 ; CPU_FREQ_BOOST_MIN=1416000 ;; # A133P family fallback
esac

export CPU_FREQ_MAX CPU_FREQ_BOOST_MIN
