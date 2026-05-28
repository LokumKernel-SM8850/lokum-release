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
# ${RELEASE_TITLE:-LokumKernel $KERNEL_BASE ${RELEASE_ID##*-}}

- Device: $DEVICE_MARKETING_NAME
- Codename: $DEVICE_CODENAME
- Supported codenames: ${SUPPORTED_CODENAMES:-$DEVICE_CODENAME}
- Runtime tested: ${RUNTIME_TESTED_CODENAMES:-not recorded}
- Firmware: $FIRMWARE_ID
- Kernel: $KERNEL_RELEASE
- Features: ${FEATURE_LABEL:-KSun + SUSFS $SUSFS_VERSION}

## Files

- $RELEASE_ZIP_NAME — flashable AnyKernel3 zip
- boot-96m-fastboot-test.img — fastboot test image
- SHA256SUMS — checksums

Test the boot image first with \`fastboot boot boot-96m-fastboot-test.img\`. Flash the zip only after boot, display/touch, Wi-Fi/mobile data, KSun root, SUSFS, dmesg, and pstore checks look clean.
NOTES_EOF

if [[ -n "${STATIC_COMPATIBILITY_NOTE:-}" ]]; then
  cat >> "$NOTES" <<NOTES_EOF

## Compatibility note

$STATIC_COMPATIBILITY_NOTE

This package is boot-only. It does not replace vendor_boot, dtbo, init_boot, vbmeta, super, or firmware partitions.
NOTES_EOF
fi

printf 'Release output ready in %s\n' "$OUT_ROOT"
printf 'Release notes: %s\n' "$NOTES"
