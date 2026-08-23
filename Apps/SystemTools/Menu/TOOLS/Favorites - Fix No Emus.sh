#!/bin/sh
export PATH="/mnt/SDCARD/System/bin:/mnt/SDCARD/System/usr/trimui/scripts:$PATH"
export LD_LIBRARY_PATH="/mnt/SDCARD/System/lib:/usr/trimui/lib:$LD_LIBRARY_PATH"

/mnt/SDCARD/System/usr/trimui/scripts/infoscreen.sh -m "Fixing favorites..."

timestamp=$(date +'%Y%m%d-%Hh%M')
set -eu

ROMS_DIR=/mnt/SDCARD/Roms
FAV_FILE=favourite2.json

cd $ROMS_DIR
cp $FAV_FILE "${FAV_FILE}_$timestamp"

sed -i 's/^{.*,"label/{"label/' "$FAV_FILE"
awk '{
  sublabel = ""
  if (match($0, /sublabel":"[^"]*"/)) {
    sublabel = substr($0, RSTART + 11, RLENGTH - 12)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", sublabel)
  }
  if (sublabel == "") {
    emudir = ""
    if (match($0, /rompath":"[^"]*"/)) {
      rp = substr($0, RSTART + 10, RLENGTH - 11)
      n = split(rp, parts, "/")
      for (i = 1; i <= n; i++) {
        if (parts[i] == "Roms" && i < n) { emudir = parts[i + 1]; break }
      }
    }
    if (emudir != "") {
      sub(/sublabel":"[^"]*"/, "sublabel\":\"" emudir "\"")
    }
  }
  print
}' "$FAV_FILE" >favourite2_fixed.json
mv favourite2_fixed.json $FAV_FILE

sync
sleep 1

# Fix emulator path

favourite_file="/mnt/SDCARD/Roms/favourite2.json"

get_launch_from_config() {
  local emulator_path="$1"
  local config_file="${emulator_path}config.json"

  if [ -f "$config_file" ]; then
    launch=$(jq -r '.launch' "$config_file")
    echo "$launch"
  else
    echo "Error: The config.json file for $emulator_path does not exist."
    return 1
  fi
}

temp_fav_file="/mnt/SDCARD/Roms/favourite2.json.updated"
>"$temp_fav_file"

while IFS= read -r line; do
  if echo "$line" | jq empty >/dev/null 2>&1; then
    launch_path=$(echo "$line" | jq -r '.launch')
    emulator_dir=$(dirname "$launch_path")
    new_launch=$(get_launch_from_config "$emulator_dir/")
    if [ $? -eq 0 ] && [ -n "$new_launch" ]; then
      full_launch_path="$emulator_dir/$new_launch"
      updated_line=$(echo "$line" | jq -c --arg new_launch "$full_launch_path" '.launch = $new_launch')
      echo "$updated_line" >>"$temp_fav_file"
    else
      echo "$line" >>"$temp_fav_file"
    fi
  else
    echo "JSON format error in a line of the favourites file, line skipped."
  fi
done <"$favourite_file"

mv "$temp_fav_file" "$favourite_file"
echo "Update completed."
