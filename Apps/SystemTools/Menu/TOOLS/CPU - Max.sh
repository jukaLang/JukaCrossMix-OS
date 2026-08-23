#!/bin/sh

output_file="/tmp/cpumax.sh"

/mnt/SDCARD/System/usr/trimui/scripts/infoscreen.sh -m "Applying \"$(basename "$0" .sh)\"."

CPU_led_Loop() {
    cat <<'EOF'
#!/bin/sh
# Apply the device's true maximum frequency (stock kernels reject 2000 MHz)
. /mnt/SDCARD/System/etc/cpu_profiles.sh

while true; do

    echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
    echo "Set CPU governor to performance."
    for CPU in /sys/devices/system/cpu/cpu[0-3]; do
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
