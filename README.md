# LokumKernel_SM8850 Release Tools

This repository is the release/orchestration layer for LokumKernel on Xiaomi SM8850 Pandora-class devices.

It does **not** store generated boot images, stock firmware images, downloaded APKs, or flashable zip artifacts in Git. Those belong in `out/` locally and in GitHub Releases after tagging.

## Layout

```text
manifests/                  pinned device/release metadata
scripts/build.sh             Kleaf build wrapper
scripts/verify.sh            boot image and config verifier
scripts/package-anykernel3.sh AnyKernel3 zip packager with arm64 Magisk tools
scripts/release.sh           build + verify + package + release notes
scripts/ci/                  guarded self-hosted auto-build/pre-release helpers
.github/workflows/           GitHub Actions workflow for CI-assisted releases
docs/                        flashing, testing, update, GitHub setup docs
out/                         ignored generated artifacts
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

Future remote:

```text
git@github.com:LokumKernel-SM8850/lokum-release.git
```

## CI-assisted releases

See `docs/CI-AUTO-RELEASE.md` for the self-hosted runner workflow that watches KernelSU Next/SUSFS upstreams and publishes verified pre-release artifacts when integration succeeds.
