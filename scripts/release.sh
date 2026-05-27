#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

"$SCRIPT_DIR/build.sh"
"$SCRIPT_DIR/verify.sh"
"$SCRIPT_DIR/package-anykernel3.sh"

NOTES="$OUT_ROOT/release-notes.md"
mkdir -p "$OUT_ROOT"
cat > "$NOTES" <<NOTES_EOF
# $PROJECT_NAME $RELEASE_ID

Device: $DEVICE_CODENAME
Firmware base: $FIRMWARE_ID / Android $ANDROID_VERSION
Kernel release: $KERNEL_RELEASE
KernelSU Next: $KERNELSU_NEXT_HEAD
SUSFS: $SUSFS_VERSION ($SUSFS_SOURCE_HEAD)
Boot image size: $BOOT_IMAGE_SIZE bytes

## Artifacts

- $RELEASE_ZIP_NAME — preferred AnyKernel3 permanent install package
- boot-96m-fastboot-test.img — raw fastboot boot test image
- SHA256SUMS — artifact checksums

## Required test gate

1. Test raw image first: \`fastboot boot boot-96m-fastboot-test.img\`.
2. Verify boot complete, touch/display, Wi-Fi, mobile data, KernelSU root, SUSFS version/features, dmesg, and pstore.
3. Only after runtime validation, flash the AnyKernel3 zip through KernelFlasher/recovery.
NOTES_EOF

printf 'Release output ready in %s\n' "$OUT_ROOT"
printf 'Release notes: %s\n' "$NOTES"
