<div align="center">
### One OS for every TrimUI handheld.

Smart Pro · Smart Pro S · Brick · Brick Pro — auto-detected, auto-tuned.

[![Latest Release](https://img.shields.io/github/v/release/jukaLang/JukaMix-OS?style=for-the-badge&color=6c5ce7)](https://github.com/jukaLang/JukaMix-OS/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/jukaLang/JukaMix-OS/total?style=for-the-badge&color=00b894)](https://github.com/jukaLang/JukaMix-OS/releases)
[![License](https://img.shields.io/github/license/jukaLang/JukaMix-OS?style=for-the-badge)](LICENSE)
[![Discord](https://img.shields.io/badge/Discord-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/R9qgJjh5jG)
[![Patreon](https://img.shields.io/badge/Patreon-F96854?style=for-the-badge&logo=patreon&logoColor=white)](https://www.patreon.com/c/JukaLang)
[![Stars](https://img.shields.io/github/stars/jukaLang/JukaMix-OS?style=for-the-badge&color=fdcb6e)](https://github.com/jukaLang/JukaMix-OS/stargazers)

**[⬇️ Download](https://github.com/jukaLang/JukaMix-OS/releases/latest)** ·
**[📖 Docs](https://github.com/jukaLang/JukaMix-OS/wiki)** ·
**[💬 Discord](https://discord.gg/R9qgJjh5jG)** ·
**[🎨 Themes](Themes/)**

</div>

---

## Why JukaMix?

JukaMix OS delivers a powerful, customizable experience — with improved settings, new features,
updated emulators, and additional apps. It's completely free and open source.

| | JukaMix OS |
|---|---|
| **Every TrimUI handheld** | Smart Pro, Smart Pro S and Brick from one image — performance profiles, emulator tuning and PortMaster setup adapt automatically to the running device |
| **Backed-up updates** | The installer backs up the files it replaces and checks free space before it runs — your ROMs, BIOS files, saves and themes live outside the image, so an update never overwrites them |
| **Protected user data** | ROMs, BIOS, saves, states, screenshots and themes are on protected paths — the updater refuses to modify them |
| **No computer needed** | Wi-Fi → Control Center → System Update. A background checker toasts you when a release lands |
| **Verifiable downloads** | Every release publishes `SHA256SUMS.txt` next to the image, so an update can be checksum-verified before it is installed |
| **Self-healing PortMaster** | Missing, broken, or copied without exec bits? It repairs itself on launch |
| **Built for creators** | Themes, icon packs, backgrounds, "Best" templates and automatic overlays |
| **Python & Go support** | Run Python scripts and compile Go programs directly on device |

---

## Development Tools

JukaMix OS includes built-in development tools for scripting and programming:

### Python Support
- **Python 3.11** runtime for running `.py` scripts
- **pip** package manager for installing libraries
- **Apps/PythonRunner** — Easy script execution and interactive shell

### Go Compiler
- **Go 1.22** toolchain for building `.go` programs
- **go build/run/get** — Full development workflow
- **Apps/GoCompiler** — Build, run, and manage Go projects

### Buildroot Environment
- **Full Linux chroot** with modern glibc 2.44
- **GPU/Audio/Input passthrough** for advanced development
- **OverlayFS** for persistent package installs

---

## JukaMix vs other CFWs

On the Smart Pro / Smart Pro S / Brick you have a handful of custom-firmware options. They
split into three philosophies (the last one on different hardware):

- **Keep the stock firmware** — JukaMix and (historically) Tomato run as a layer on
  top of the TrimUI firmware, so you keep its drivers, hardware video decode and power
  management. Everything is on the SD card: remove it and the device is stock again.
- **Replace the OS** — Knulli and MinUI boot their own system. You gain
  control and polish, but trade away the stock firmware's device-specific tuning.


| CFW | Devices | Base | Updates | Standout | Watch out |
|---|---|---|---|---|---|
| **JukaMix OS** | Smart Pro, Smart Pro S, Brick, Brick Pro | Stock firmware | Transactional, in-app over Wi-Fi | One image tuned for all four devices; transactional updates with rollback | Younger project; TrimUI devices only |
| **Knulli** | Broad — many handhelds | Batocera / EmulationStation, standalone OS | Full-image reflash | Desktop-grade emulation: scrapers, themes, Bluetooth, netplay | Heavier and slower to boot; higher idle power draw |
| **Tomato OS** | Original TrimUI Smart only | Stock firmware | Full-image | Pioneering enhanced OS (70+ emulators, ports) for its day | Discontinued; not for the Smart Pro / Smart Pro S / Brick |
| **MinUI** | Many devices — TrimUI builds are **Legacy** | Minimal libretro launcher | Full-image | Zero-config: boots straight to games, auto-resume | No settings, boxart or themes by default; TrimUI builds being retired |

### JukaMix OS

**Advantages** — runs on the stock TrimUI firmware (its drivers, hardware video decode and
sleep behavior stay intact); one image covers the Smart Pro, Smart Pro S and Brick with
per-device CPU/game profiles applied automatically; transactional updates that back up,
journal and roll back; the updater refuses to touch `Roms/`, `BIOS/`, saves or themes;
self-healing PortMaster, Python, glibc and the Wi-Fi Control Center; GPL-3.0 open source.

**Disadvantages** — TrimUI devices only; it's a layer on the stock firmware, so it inherits
stock quirks (and a TrimUI firmware update can change behavior underneath it); younger and
smaller community than Knulli.

### Knulli

**Advantages** — a true standalone OS (Batocera base) with EmulationStation's whole world:
automatic scraping, thousands of themes, Bluetooth controllers, netplay, per-system config;
one setup carries across many handhelds, not just TrimUI.

**Disadvantages** — much heavier: slower boot and higher power draw than the stock-based
options; full-image reflash to update; on TrimUI devices the hardware acceleration and
sleep/power behaviour historically lag the stock firmware's.

### Tomato OS

**Advantages** — in its time (2022–2023) a pioneering enhanced OS for the original TrimUI
Smart, with 70+ built-in emulators, ports and customization.

**Disadvantages** — built for the original TrimUI Smart only and no longer maintained; it
does **not** run on the Smart Pro, Smart Pro S or Brick. Listed here mainly so you don't
install it by mistake.

### MinUI

**Advantages** — the definition of simple: no settings, no boxart, no themes, no cruft; boots
fast, sips battery, auto-sleeps, and resumes exactly where you left off; the same card works
across many different handhelds.

**Disadvantages** — by design it has none of the comforts (scraping, artwork, PortMaster,
Wi-Fi apps) and no tuning; and on TrimUI specifically the Smart Pro and Brick builds are
marked **Legacy** — the project says they "will be retired in a future update", so it's a
risky pick for a daily driver.

> The short version: want the stock experience with safe updates across all four devices?
> That's JukaMix. Want a completely different, feature-dense OS? Knulli. Want
> bare-bones speed? MinUI.

---

## Install

> First time on JukaMix? Start here. Already running it? Skip to [Updating](#updating).
>
> **📖 Full installation guide:** See [docs/INSTALLATION.md](docs/INSTALLATION.md) for detailed
> instructions including rootfs setup, package system (.ipk), and troubleshooting.

### What you need

| Item | Requirement |
|------|-------------|
| **microSD card** | FAT32, 32 GB or larger recommended (holds OS + ROMs) |
| **Card reader** | Any USB or built-in reader works |
| **Computer** | Windows, macOS, or Linux — any will do |
| **TrimUI device** | Smart Pro, Smart Pro S, Brick, or Brick Pro |

> **One image works on all four devices** — there is no per-device download.

---

### Step 1 — Format the card

Format the card as **FAT32**, single partition.

<details>
<summary><b>Windows</b></summary>

1. Right-click the card → **Format**
2. Set **File system** to **FAT32**
3. Click **Start**

> **Cards over 32 GB?** The built-in formatter may only offer exFAT/NTFS.
> Use [Rufus](https://rufus.ie), [guiformat](https://www.ridgecrop.demon.co.uk/guiformat.htm),
> or the Raspberry Pi Imager instead.

</details>

<details>
<summary><b>macOS</b></summary>

1. Open **Disk Utility**
2. Select the card in the sidebar
3. Click **Erase**
4. Set **Format** to **MS-DOS (FAT32)**
5. Click **Erase**

</details>

<details>
<summary><b>Linux</b></summary>

```bash
# Identify the card (e.g. /dev/sdb)
lsblk

# Format as FAT32 (REPLACES ALL DATA!)
sudo mkfs.vfat -F 32 /dev/sdX1
```

</details>

---

### Step 2 — Download

👉 **[Download latest release](https://github.com/jukaLang/JukaMix-OS/releases/latest)**

Grab the `JukaMix_<stamp>.zip` file (e.g. `JukaMix_0821202601.zip`).

> The stamp is the build date+hour: `MMDDYYYYHH`
> So `0821202601` = August 21, 2026 at 01:00

---

### Step 3 — Extract to the card root

Extract the archive to the **root** of the SD card — **not into a subfolder**.

✅ **Correct** — You should see this at the card root:
```
SD Card/
├── Apps/
├── Emus/
├── Roms/
├── System/
└── trimui/
```

❌ **Wrong** — These mean you extracted incorrectly:
```
SD Card/
└── JukaMix_0821202601/    ← DO NOT extract to a subfolder
    ├── Apps/
    └── ...
```

<details>
<summary><b>Extraction tips by OS</b></summary>

| OS | Tool | Notes |
|----|------|-------|
| **Windows** | [7-Zip](https://www.7-zip.org/) | Right-click → Extract Here (preserves permissions) |
| **Windows** | WinRAR | Drag contents directly to SD card |
| **macOS** | Built-in | Double-click zip, drag contents to card |
| **Linux** | `unzip` | `unzip JukaMix_*.zip -d /path/to/sdcard` |

</details>

---

### Step 4 — First boot

1. **Safely eject** the SD card from your computer
2. **Insert** the card into your TrimUI device
3. **Power on** — first boot takes 2-5 minutes while the system initializes

> **What to expect:** The screen may go black briefly, show a JukaMix logo, then load the menu.
> This is normal on first boot.

<details>
<summary><b>🔧 Firmware update wizard (if prompted)</b></summary>

If your TrimUI firmware is older than JukaMix requires, a firmware wizard runs automatically:

1. **Press A** when prompted to start the update
2. **Do NOT remove the card** or turn off the device
3. **Wait** for the device to power off automatically
4. **Power back on** — the firmware will be flashed

> This only happens once. See `trimui/firmwares/MinFwVersion.txt` for the required version.

</details>

<details>
<summary><b>🔧 Stock launcher appears instead of JukaMix?</b></summary>

This usually means the SD card isn't set as the boot source:

- **Smart Pro:** Go to **Settings → Boot Source → SD Card**
- **Smart Pro S:** Go to **Settings → Boot Source → SD Card**
- **Brick/Brick Pro:** Boots from SD automatically (no setting needed)

If the option doesn't appear, try reformatting the card and re-extracting the archive.

</details>

<details>
<summary><b>🔧 Screen flickering or menu crashes?</b></summary>

If you see flickering or the menu crashes:

1. Power off the device (hold power button for 5 seconds)
2. Remove the SD card
3. On a computer, delete `System/usr/trimui/crossmix-version.txt` from the card
4. Reinsert the card and power on — JukaMix will re-initialize

If this persists, re-extract the archive to the card.

</details>

---

### Step 5 — Add your content

Drop your ROMs and BIOS files into the correct folders:

| Content | Where | Example |
|---------|-------|---------|
| **ROMs** | `Roms/<SYSTEM>/` | `Roms/GBA/zelda.gba` |
| **BIOS** | `BIOS/` | `BIOS/scph1001.bin` |
| **Themes** | `Themes/` | `Themes/MyTheme.7z` |
| **Icon packs** | `Icons/` | `Icons/MyIcons/` |
| **Wallpapers** | `Backgrounds/` | `Backgrounds/GBA/wallpaper.png` |

**Supported systems include:**
`GB`, `GBA`, `GBC`, `NES`, `SNES`, `Genesis`, `PS1`, `N64`, `PSP`, `NDS`, `DC`, `MAME`, `Arcade`, `Neo Geo`, and [many more](Emus/).

> **BIOS help:** Each emulator may require specific BIOS files. Check `Emus/<platform>/` for
> BIOS requirements — look for files named `*.bin` or `*.rom` in the folder.

> **Themes are drop-in:** Just drop `.7z` theme files into `Themes/`. They appear in the
> theme selector automatically.

---

### Quick check ✅

After first boot, verify everything works:

- [ ] Menu loads and is responsive
- [ ] System shows correct device name in **System Info**
- [ ] At least one game launches
- [ ] Wi-Fi connects (for updates)

**All good?** You're ready! Head to [Updating](#updating) to learn about OTA updates.
**Issues?** See [Troubleshooting](#troubleshooting) or ask on [Discord](https://discord.gg/R9qgJjh5jG).



---

## Updating

Updating is one tap, no computer required:

1. Connect the handheld to Wi-Fi.
2. Open **Apps → JukaMix Control Center → System Update** (or the standalone **System Update** app).
3. Confirm the download.

JukaMix resolves the latest GitHub release, downloads the image and applies it in place. The
installer backs up the files it replaces (system, emulators, apps, RetroArch), checks that the card
has enough free space first, and restores saves, BIOS files, PortMaster data and settings afterwards.
ROMs, BIOS files, saves, states, screenshots and themes live outside the image, so an update never
overwrites them.

<details>
<summary><b>Offline update (no Wi-Fi)</b></summary>

1. Download the latest `JukaMix_<stamp>.zip` from GitHub Releases on any computer.
2. Copy it to the **root** of the SD card.
3. Open **Apps → System Update** and apply it — or just reboot, and the legacy updater picks up
   the archive from the SD root.

</details>

---

## Supported devices

| Device | Code | SoC | GPU | Display | Notes |
|---|---|---|---|---|---|
| **TrimUI Smart Pro** | `tsp` | Allwinner A133 Plus | Mali-G31 | 1280×720 (16:9) | Flagship target, dual analog |
| **TrimUI Smart Pro S** | `tsps` | Allwinner A523 | Mali-G57 | 1280×720 (16:9) | Fastest of the three, dual analog |
| **TrimUI Brick** | `brick` | Allwinner A133 Plus | Mali-G31 | 1024×768 (4:3, touch) | No analog sticks, no rumble |
| **TrimUI Brick Pro** | `brickpro` | Allwinner A133 Plus | Mali-G31 | 1280×720 (16:9) | Same as Smart Pro, dual analog |

Every emulator launcher tunes the CPU to its device's own ceiling via
`cpufreq.sh ondemand 2 "${JUKAMIX_CPUFREQ_MAX:-6}"`: **Smart Pro S** runs at up to
2.0 GHz, **Smart Pro** and **Brick Pro** at 1.8 GHz and **Brick** at 1.6 GHz (the `[recommended_defaults]` of each
`Profiles/DEVICE-OVERRIDES/*_base.cfg`). Launchers written for the faster A523 are clamped to the
closest valid frequency on the A133 instead of being rejected, so the same image tunes every
device correctly.

**Per-game profiles** in `Profiles/<system>/` (e.g. `Profiles/DC/SonicAdventure.cfg`) apply
automatically when that game launches. The applier (`apply_game_profile.sh`) clamps each
profile's frequencies to the running device's ladder, so a profile tuned on the Smart Pro S
applies safely on the Smart Pro and Brick too — a profile verified for another device warns, and
`--strict` refuses it.

---

## PortMaster, made simple

PortMaster ships pre-installed in **Apps → PortMaster**, with a second entry in the **PORTS** tab.
Both entry points self-heal: if PortMaster is missing, broken, or was copied onto the SD card
without execute permissions, it is repaired automatically on launch. Ports live in `Data/ports/`
and appear in the PORTS tab automatically.

Drop any port zip into `Apps/PortMaster/PortMaster/autoinstall/` and open the PortMaster app —
it installs them for you.

<details>
<summary><b>The <code>jm-portmaster</code> CLI</b></summary>

From the terminal or over SSH:

```bash
jm-portmaster status    # what is installed, where, and how healthy
jm-portmaster install   # download + install the latest official release
jm-portmaster ensure    # install only if missing/broken (no-op when healthy)
jm-portmaster fix       # repair exec bits, Data/ports, launcher (offline)
jm-portmaster launch    # ensure, then open the PortMaster GUI
```

Downloads are checksum-verified against PortMaster's published MD5.

**Offline install:** grab `trimui.portmaster.zip` from the PortMaster-GUI releases page, copy it
to the SD card, then run:

```bash
jm-portmaster install --from-zip /mnt/SDCARD/trimui.portmaster.zip
```

</details>

---

## Built-in tools

Python 3.11 ships in the image (`System/bin/python3.11` with Pillow and pip), and
several utilities are built on top of it. Find them under **Apps → System Tools → TOOLS**:

| Tool | What it does |
|---|---|
| **Find Duplicate Roms** | Hashes every ROM per system (size + md5) and stashes exact duplicates into `Data/duplicates/<system>/`. Files are moved, never deleted. |
| **Test ROM Archives** | Checksum-tests every `.zip` per system and stashes broken archives into `Data/archives-corrupt/<system>/`. Also moved, never deleted. |
| **Optimize Boxart Images** | Shrinks boxart in `Imgs/` down to 512 px with Pillow and re-saves optimized; only overwrites when the result is smaller. |
| **M3U Playlist Generator** | Creates multi-disc playlists from `(Disc 1)`/`[Disc 2]`-style files in `Roms/`. |

Add your own Python tools the same way: a script in `System/usr/trimui/scripts/` plus a launcher
in `Apps/SystemTools/Menu/TOOLS/` that calls `python3.11` (see the existing entries for the
`LD_LIBRARY_PATH`/`PATH` setup and the `TOTAL_*=` output convention the UI parses).

**Recent-glibc software:** the image bundles glibc **2.44** in `System/lib/glibc/` (loader + core
libs), so anything built against a newer glibc than the firmware ships still runs. Use the
`jm-glibc` wrapper — `jm-glibc /path/to/binary [args…]` — which invokes the bundled loader
directly; update the runtime from the Debian `libc6` package (see `System/lib/glibc/README.md`).

---

## Analog sticks

TrimUI pads are not plain evdev controllers. The stick MCUs talk to `trimui_inputd` over a UART,
the daemon applies the calibration in `/mnt/UDISK/joypad.config` (left) and `joypad_right.config`
(right) and publishes the result as `TRIMUI Player1..4` — the devices every emulator, MainUI and the
firmware's calibration screen read. That is why a stick can look perfect in the calibration screen
and still move the wrong way in a game.

Everything below is read from the running system, nothing is hardcoded per model:

| Device | Sticks | Calibration the daemon reads | Input daemon on the card |
|---|---|---|---|
| Smart Pro (`tsp`) | left + right | `joypad.config`, `joypad_right.config` | `System/resources/tsp_inputd` — universal TG5040/TG5050 build, pad over `/dev/ttyS*` |
| Smart Pro S (`tsps`) | left + right | same | `System/resources/tsps_inputd` — the same universal build, pad over `/dev/ttyAS*` |
| Brick (`brick`) | none | – | the firmware's own `/usr/trimui/bin/trimui_inputd` (the OS builds have no stick support) |
| Brick Pro (`brickpro`) | left + right | same | `System/resources/brickpro_inputd` — pad over I2C, no configurable polling rate |

| Symptom | Cause | Fix |
|---|---|---|
| Horizontal input flipped in games, fine in the calibration screen | the pad frame reports left/right the other way round (depends on the unit's pad revision), so the analog axis (`ABS_X`) is mirrored while the calibration screen — which only proves the range — still looks right | **System Tools → CONTROLS → Analog Sticks → Direction test**, then **Enable mirror fix** (a reversible swap of RetroArch's `input_player1_*_x_*_axis` bindings) |
| One half of a stick does nothing | calibration whose `min`/`max` no longer bracket `zero` — e.g. a `joypad.config` restored from another device or an older firmware | Same menu → **Clear calibration (recalibrate)**, then Settings → System → Calibrate Joystick |
| Pad buttons/d-pad wrong after moving the SD card between devices | the installed daemon is the old TG5040-only build (or the wrong build for this SoC) | automatic at boot; manual: **Analog Sticks → Reinstall input daemon** or `inputd_switcher.sh verify` |
| Mirror fix “on” in the menu but games are mirrored again | an OS update, a firmware-settings restore or a RetroArch config reset rewrote `retroarch.cfg` | **Re-apply mirror fix** in the same menu (the boot check usually does it first) |

Why the mirror fix writes a binding instead of editing one: the shipped `retroarch.cfg` leaves every
stick axis at `"nul"` — RetroArch maps the pad on its own — so “invert the value in the file” would
write `"nul"` back and change nothing. The fix therefore writes an explicit binding, and because
RetroArch numbers analog axes by position rather than by evdev code (with its `sdl2` joypad driver:
`ABS_X`, `ABS_Y`, then the remaining axes in code order), the direction test records which code the
stick really moves and binds that index. Pads that number their right stick differently therefore
still get the right axis, and the report prints the numbering it found.

The commands behind that menu entry (log: `Apps/SystemTools/Logs/Analog Sticks.log`):

| Command | What it does |
|---|---|
| `stick_diag.sh report` | device/SoC, which daemon copy is running and what it talks to, calibration verdicts, published input devices, the RetroArch axis numbering, workaround state and a one-line verdict |
| `stick_diag.sh status` | one line summary for menus/logs; exits `2` when a calibration is broken or the workaround fell out of `retroarch.cfg` |
| `stick_diag.sh test [secs]` | guided direction test: push each stick as asked, it compares the analog axis **and** the d-pad bits with the expected direction, names the layer that mirrors and binds the stick it measured |
| `stick_diag.sh flip on [l\|r\|both]` / `flip off` | apply/undo the RetroArch mirror fix (default: left stick; the menu asks which one). Originals are remembered in `System/etc/analog_x_flip.cfg` (and in the log), asking again for a stick that is already flipped re-applies the recorded binding instead of inverting twice |
| `stick_diag.sh flip reapply` | write the recorded binding back into `retroarch.cfg` after an update or a restore replaced it; bindings changed by hand are left alone unless this is called explicitly |
| `stick_diag.sh verify` | reinstall the input daemon when it does not match this device, then report |
| `stick_diag.sh reset` | archives `joypad.config`/`joypad_right.config` so they can be recalibrated |
| `stick_diag.sh ensure` | boot-time repair: quarantines only calibration files the daemon cannot use, keeps the input daemon in sync with the device and heals a dropped mirror fix |

The daemon is device specific: `System/resources/{tsp,tsps}_inputd` is one universal build that picks
TG5040 (Smart Pro) or TG5050 (Smart Pro S) from `/proc/cpuinfo`, while the older build shipped in
`trimui/app/` knows only TG5040; the Brick Pro build polls its pad over I2C instead of a UART.
`System/starts/°customization.sh` re-checks the installed copy at every boot (and detects the device
from `/proc/cpuinfo` when `/etc/trimui_device.txt` is not there yet), so a card moved between devices
can no longer run the wrong pad mapping. The mirror fix covers RetroArch; standalone emulators
(PPSSPP, flycast, Yaba Sanshiro, …) keep their own mapping tables and need the same swap in their own
config.
---

## Customise it

JukaMix is built for creators. Everything below is drop-in — no rebuild required.

| Folder | What goes there |
|---|---|
| `Themes/` | Full UI themes |
| `Icons/` | Icon packs |
| `Backgrounds/` | Wallpapers per system |
| `Best/` | Curated game-collection templates |

Made something good? Open a PR — community themes and icon packs are very welcome.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the format spec and submission process.

Best pack folders must not contain spaces — the on-device name comes from the pack's
`config.json` `label`, not the folder name (see `Best/FreeGamesCollection/`).

---

## Troubleshooting

| Problem | Quick Fix |
|---------|-----------|
| **Stock launcher appears** | Settings → Boot Source → SD Card (Brick: automatic) |
| **Screen flickering** | Delete `System/usr/trimui/crossmix-version.txt`, reboot |
| **A game or app crashed / will not start** | System Tools → TOOLS → **System Logs - Collect**: it writes `System/logs/diagnostics_<stamp>.txt` (a summary, recent crashes, every launch and how it ended, plus the preserved runtime logs) — share that file when reporting a problem |
| **The console froze / needed a hard reset** | Same report: it dates the last time the device was known alive and flags a previous session that ended without a clean shutdown, names the app that was running and says whether the whole system had already stopped working, so a hang can be blamed on the app rather than on "the device froze" |
| **Not sure a crash would be recorded at all** | System Tools → TOOLS → **System Logs - Verify**: it checks that the boot, launcher and shutdown hooks are really wired up, replays a crash, a hang (including what the last watchdog ticks saw), an app that stops using CPU and a power pull in a throwaway sandbox, and reports what it cannot confirm |
| **Games not showing** | Check ROMs are in `Roms/<SYSTEM>/` with correct extension |
| **No sound** | Check volume buttons, Settings → Sound |
| **Wi-Fi won't connect** | Toggle Wi-Fi, reboot, check 2.4GHz network |
| **Slow performance** | Use Performance Profiles, check game compatibility |
| **Analog stick left/right flipped in games** | System Tools → CONTROLS → Analog Sticks → **Direction test**, then **Enable mirror fix** |
| **Half of a stick dead / stick drifts** | Same menu → **Clear calibration**, then recalibrate (Settings → System → Calibrate Joystick) |
| **Device won't boot** | Remove SD card → reformat FAT32 → re-extract archive |

> **📖 Full troubleshooting guide:** See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
> for detailed solutions to common issues.

---

## Repository layout

A few boundaries are worth knowing before you poke around:

| Path | What it is |
|---|---|
| `System/bin/`, `System/lib/` | Prebuilt runtime payload shipped in the image: third-party binaries (`bash`, `curl`, `7zz`, `ffmpeg`, …) and shared libraries, installed at `/mnt/SDCARD/System/bin` and `/mnt/SDCARD/System/lib`. `System/bin` is on `PATH` on-device. |
| `bin/`, `lib/`, `migrations/`, `config/` | JukaMix's own tooling (`jm-update`, `jm-opkg`, `jm-portmaster`, …). `install.sh` copies these into `System/usr/jukamix/{bin,lib,migrations}` on the device. `/mnt/SDCARD/bin` is added to `PATH` (after `System/bin`, so nothing is shadowed) — `jm-opkg`, `jm-doctor`, etc. are invocable directly. |
| `scripts/`, `tests/`, `_assets/` | Host-side build and validation tooling — `fetch_cores.sh`, `validate_image.sh`, the off-device test suites and the fetched firmware blobs. **Excluded from the release image**; never needed on the SD card. |
| `tools/` | Build tooling that **also ships** in the image — JukaHub, System Update and `jukamix-validate` read `/mnt/SDCARD/tools/` on-device. |
| `Roms/`, `BIOS/`, `Saves/`, `States/`, `Pictures/screenshots/`, `Themes/` | Protected user-data paths — an update never modifies them. The repo tracks only scaffolding (`.gitkeep`) and OS-provided content such as emulator bezels or machine definitions; user files never belong in git. |
| `RetroArch/default_config.7z` | Built by the release workflow from the image's `retroarch.cfg` and `.retroarch/config/`; the **Reset RetroArch configuration** tool extracts it on device. Never committed. |
| `trimui/firmwares/` | TrimUI firmware blobs (tracked in git), used by the firmware update/backup flow. |
| `RetroArch/.retroarch/cores/cores.7z` | Compressed RetroArch cores archive (~335MB, 165 cores). Too large for git; hosted at [jukaLang/Packages](https://github.com/jukaLang/Packages/releases/tag/cores) and downloaded at build time via `scripts/fetch_cores.sh`. Never committed to git. |

---

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) to get started,
and [SUPPORT.md](SUPPORT.md) if you need help rather than want to file a bug.
Join the conversation on [Discord](https://discord.gg/R9qgJjh5jG).

Shell tooling has off-device tests that need no hardware — they build a simulated device tree
through the `JUKAMIX_*` overrides and drive the guided stick test from a stub `evtest`:

```sh
sh tests/stick_diag_test.sh        # stick diagnostics, mirror fix, self-heal, per-device paths
sh tests/inputd_switcher_test.sh   # daemon install/verify per device, polling-rate modes
sh tests/retroarch_launcher_test.sh # RetroArch launcher env, RA_DIR and inputd handshake
sh tests/logging_test.sh           # crash/session logs, watchdog + hang autopsy, diagnostics report, self-check
```

The logging test also covers the crash-reporting plumbing described under
[troubleshooting](#troubleshooting): the append/rotate helper, the boot and launch
hooks, the watchdog tick and its hang autopsy (which app was running, whether the
system had already stopped working, and when an app stops using CPU), the report
`System/logs/diagnostics_<stamp>.txt`, and the `System Logs - Verify` self-check
(including that a hook stripped out of the boot sequence fails it).

<details>
<summary><b>Release pipeline (maintainers)</b></summary>

Releases are built by [`.github/workflows/JukaMix-OS Release.yml`](.github/workflows/JukaMix-OS%20Release.yml):
every push to `main` (or a manual workflow run) publishes a new one. The workflow

1. fetches the RetroArch cores archive (`scripts/fetch_cores.sh`),
2. validates the image (`scripts/validate_image.sh` — JSON configs, `dash -n` on every image
   script, bash-ism and theme checks),
3. removes host-side tooling before archiving (`_assets`, `scripts`, `tests`, `schemas`,
   `packages`, `.github`, `README.md`, leftover `.gitkeep`s) and bundles
   `RetroArch/default_config.7z` for a faster first boot,
4. zips the tree as `JukaMix_<MMDDYYYYHH>.zip` and, because GitHub caps a release asset at
   2 GiB and the image is ~4.4 GB, splits it into 1900 MB volumes (`.001`, `.002`, …);
   7-Zip/WinRAR open `.001` directly, plain `7z x` reassembles them,
5. publishes the archive part(s) together with `SHA256SUMS.txt`.

The stamp comes from the date and hour, so every build is a new version. Rebuilding within the
same hour overwrites that hour's release, and `releases/latest` always points at the newest
build; the on-device update check simply reports no update until the first release exists.

</details>

---

## Attribution

JukaMix OS includes work from **PortMaster** (Kloptops), **Schmurtzm's** scripts, and many
community contributors. All included third-party components remain subject to their respective
licenses and copyrights.

Licensed under [GPL-3.0](LICENSE).

<div align="center">
<sub>Made by the Juka project · <a href="https://discord.gg/R9qgJjh5jG">Discord</a> · <a href="https://github.com/jukaLang">GitHub</a></sub>
</div>
