#!/bin/sh

output_file="/tmp/cpumax.sh"

/mnt/SDCARD/System/usr/trimui/scripts/infoscreen.sh -m "Max CPU performance: locking to the device ceiling."

CPU_led_Loop() {
    cat <<'EOF'
#!/bin/sh
# Apply the device's true maximum frequency (the A133P stock kernel has no
# 2000 MHz step; the A523-based Smart Pro S does)
. /mnt/SDCARD/System/etc/cpu_profiles.sh

while true; do

    echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
    echo "Set CPU governor to performance."
    for CPU in /sys/devices/system/cpu/cpu[0-9]*; do
        # Set minimum frequency
        echo -n "$CPU_FREQ_MAX" > "$CPU"/cpufreq/scaling_min_freq
        echo "Set minimum CPU frequency to $CPU_FREQ_MAX for $CPU."

        echo -n "$CPU_FREQ_MAX" > "$CPU"/cpufreq/scaling_max_freq
        echo "Set maximum CPU frequency to $CPU_FREQ_MAX for $CPU."
    done
    sleep 3
done

EOF
}

CPU_led_Loop >"$output_file"

chmod a+x "$output_file"

pkill -f "cpumax.sh"
"$output_file" &

sleep 0.1
