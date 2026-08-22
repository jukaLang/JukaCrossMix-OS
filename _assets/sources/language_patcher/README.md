# CrossMix-OS Language Patcher

This repository contains tools to manage and patch language files for CrossMix-OS on TrimUI devices (Smart Pro, Brick, Smart Pro S).

## Problem Statement

MainUI (the interface for TrimUI consoles) uses language files where fields are identified by a numeric ID. However, different console models (Brick, TSP, TSPS) sometimes use different labels for the same ID, particularly for hardware-specific settings (IDs >= 197).

To support all devices with a single OS image, CrossMix-OS uses a reference language set and patches it on-the-fly based on the detected device.

## Directory Structure

*   **`reference/`**: Contains the reference language files (based on CrossMix-OS/TSP stock).
*   **`stock_tg3040/`**: Stock language files for TrimUI Brick (tg3040).
*   **`stock_tg5040/`**: Stock language files for TrimUI Smart Pro (tg5040).
*   **`stock_tg5050/`**: Stock language files for TrimUI Smart Pro S (tg5050).
*   **`patches/`**: Generated JSON patch files containing device-specific overrides.

## Scripts

### 1. `generate_patches.py`

This Python script generates the patch files. It compares the reference language files with the stock files for each device.

*   **Logic**: It extracts all keys `>= "197"` from the target device's stock file.
*   **Output**: Creates files named `{lang}.{device}.patch` in the `patches/` directory (e.g., `patches/en.brick.patch`).

**Usage:**
```bash
python generate_patches.py
```

### 2. `lang_patches.sh`

This shell script is designed to run on the device. It applies the appropriate patches to the language files based on the current device.

*   **Input**:
    *   Reference language files (expected in `/mnt/SDCARD/trimui/res/lang/`).
    *   Patch files (expected in `/mnt/SDCARD/trimui/res/lang/`).
*   **Output**:
    *   Patched language files written to `/usr/trimui/res/lang/`.
*   **Logic**:
    1.  Takes the device name as an argument (`brick`, `tsp`, `tsps`).
    2.  Finds all matching `*.{device}.patch` files in the `patches/` subdirectory.
    3.  For each patch, it loads the corresponding reference file.
    4.  It removes any keys `>= 197` from the reference file that are NOT in the patch (ensuring clean state switching).
    5.  It applies the values from the patch.
    6.  Saves the result to the system directory.

**Usage (on device):**
```bash
# Example for TrimUI Smart Pro
./lang_patches.sh tsp

# Example for TrimUI Brick
./lang_patches.sh brick
```

## Workflow

1.  Update `reference/` with language files from current CrossMix, complete with files from tg5040 stock if some are missing.
2.  Update each stock language files for each device 
3.  Run `generate_patches.py` to update the `.patch` files in `patches/`.
3.  Deploy the `.patch` files (in `SDCARD/trimui/res/lang/`) and `lang_patches.sh` to SD card script folder.
4.  The OS boot scripts call `lang_patches.sh` with the detected device type to configure the correct UI labels.

## Note
Intially stock language files are coming from firmware versions:
 - tg3040 - brick: 20251126
 - tg5040 - TSP: 20251128
 - tg5050 - TSPS: 20251127

(Let's hope that TrimUI will avoid these overlaping between language files in the future to avoid to keep this patching step)