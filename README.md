# LokumKernel_SM8850 Release Tools

This repository is the release/orchestration layer for LokumKernel on the Xiaomi 17 series SM8850 family: Xiaomi 17 (`pudding`), Xiaomi 17 Pro (`pandora`), Xiaomi 17 Pro Max (`popsicle`), and Xiaomi 17 Ultra (`nezha`).

It does **not** store generated boot images, stock firmware images, downloaded APKs, ROM archives, or flashable zip artifacts in Git. Those belong in `out/` locally and in GitHub Releases after tagging.

## Safety model

LokumKernel packages are boot-only AnyKernel3 zips. They replace the kernel `Image` inside the active boot image and must not package or flash `vendor_boot`, `dtbo`, `init_boot`, `vbmeta`, `super`, or firmware partitions.

Current common SM8850 support is based on static fastboot ROM analysis showing the same stock Android 16 / 6.12 boot kernel payload across `pudding`, `pandora`, `popsicle`, and `nezha`. `pandora` has runtime proof; the other codenames should still be tested with `fastboot boot` before permanent flashing.

## Layout

```text
manifests/                   pinned family/release metadata
scripts/build.sh              Kleaf build wrapper
scripts/verify.sh             boot image and config verifier
scripts/package-anykernel3.sh AnyKernel3 zip packager with arm64 Magisk tools
scripts/release.sh            build + verify + package + release notes
scripts/ci/                   guarded self-hosted auto-build/pre-release helpers
.github/workflows/            GitHub Actions workflow for CI-assisted releases
out/                          ignored generated artifacts
```

## Quick usage

From this repository, with the Android kernel workspace two directories above by default:

```bash
scripts/release.sh
```

To verify an already-built dist:

```bash
DIST=/path/to/dist scripts/verify.sh
```

To package an already-built and verified dist:

```bash
DIST=/path/to/dist scripts/package-anykernel3.sh
```

## CI-assisted releases

The public CI path runs metadata and safety checks. Kernel builds are only published from maintainer-controlled runs.

## Public repository safety

Generated images, zips, firmware dumps, private keys, tokens, and local cache files must stay out of Git. Release artifacts belong in GitHub Releases after verification.
