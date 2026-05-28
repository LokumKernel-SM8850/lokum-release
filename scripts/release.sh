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
# LokumKernel $KERNEL_BASE ${RELEASE_ID##*-}

- Device: $DEVICE_MARKETING_NAME
- Codename: $DEVICE_CODENAME
- Firmware: $FIRMWARE_ID
- Kernel: $KERNEL_RELEASE
- Root: KSun + SUSFS $SUSFS_VERSION

## Files

- $RELEASE_ZIP_NAME — flashable AnyKernel3 zip
- boot-96m-fastboot-test.img — fastboot test image
- SHA256SUMS — checksums

Test the boot image first with \`fastboot boot boot-96m-fastboot-test.img\`. Flash the zip only after boot, display/touch, Wi-Fi/mobile data, KSun root, SUSFS, dmesg, and pstore checks look clean.
NOTES_EOF

printf 'Release output ready in %s\n' "$OUT_ROOT"
printf 'Release notes: %s\n' "$NOTES"
