DraStic shared libraries (aarch64)
==================================

This folder contains the shared libraries used by the "Drastic Advanced"
build (drastic + libadvdrastic.so) and the overlay modes.

  libSDL2-2.0.so.0        Patched SDL2 shim that hooks libadvdrastic.so
                          (provides the advanced/overlay features).
  libadvdrastic.so        Community "Advanced" plugin (extra options menus,
                          language selection). Build from the maintained
                          Advanced Drastic pak (trngaje), v0.12.0
                          (May 2026) - newer than the CrossMix-shipped build
                          and no longer needs libudev.
  libSDL2_image-2.0.so.0  SDL2_image, required by libadvdrastic.so
                          (same aarch64 build shipped with FileManager /
                          PICO-8 Wrapper).
  libjson-c.so.4          json-c. GENUINE .4 soname build from the Advanced
                          Drastic pak (previously the image's .5 build was
                          provided under the .4 name - ABI-compatible, but
                          the real .4 is now shipped instead).
  libjpeg.so.9            libjpeg. SDL2_image links against the .9 soname;
                          the image's libjpeg.so.8 (ABI-compatible with 9)
                          is provided under the .9 name.

The "Overlay" modes do NOT use this folder: they preload the enhanced
SDL2 2.0.26 runtime from ../lib/ (libSDL2-2.0.so.0.2600.1 + libfreeimage.so.3),
which is self-contained.

STILL MISSING (not available in this image)
-------------------------------------------
  libSDL2_ttf-2.0.so.0    SDL2_ttf (font rendering for the advanced menus)
  libfreetype.so.6        FreeType, required by SDL2_ttf

Until these two aarch64 libraries are added here, libadvdrastic.so cannot
load and "Drastic Advanced" runs as the base build (original CrossMix
behavior). The upstream pak has the same gap. Drop the two files into this
folder (or a future image update adds them) and the full plugin stack is
used automatically - the launcher detects the file and preloads the plugin.

Source: https://github.com/josegonzalez/minui-nintendo-ds-pak (NDS.pak
v0.12.0 release). The drastic binary itself is byte-identical to the one
shipped here (Advanced Drastic 1.0.8, md5 59a7711e...).
