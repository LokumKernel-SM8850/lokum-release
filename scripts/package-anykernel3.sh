#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command git
require_command unzip
require_command zip
require_command curl
require_command sha256sum
require_command file
require_command strings
require_command rg

IMAGE="$DIST/Image"
BOOT_IMG="$DIST/boot.img"
if [[ ! -f "$IMAGE" ]]; then
  echo "Kernel Image not found: $IMAGE" >&2
  exit 1
fi
if [[ ! -f "$BOOT_IMG" ]]; then
  echo "boot.img not found: $BOOT_IMG" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR" "$PACKAGE_OUT"
AK3_CACHE="$CACHE_DIR/AnyKernel3-$ANYKERNEL3_REF"
MAGISK_APK="$CACHE_DIR/Magisk-$MAGISK_VERSION.apk"
MAGISK_EXTRACT="$CACHE_DIR/Magisk-$MAGISK_VERSION-arm64"

if [[ ! -d "$AK3_CACHE/.git" ]]; then
  rm -rf "$AK3_CACHE"
  git clone "$ANYKERNEL3_REPO" "$AK3_CACHE"
fi
if ! git -C "$AK3_CACHE" cat-file -e "$ANYKERNEL3_REF^{commit}" 2>/dev/null; then
  git -C "$AK3_CACHE" fetch --tags --force --quiet
fi
git -C "$AK3_CACHE" checkout --quiet "$ANYKERNEL3_REF"

if [[ ! -f "$MAGISK_APK" ]]; then
  curl -L --fail -o "$MAGISK_APK" "$MAGISK_APK_URL"
fi
printf '%s  %s\n' "$MAGISK_APK_SHA256" "$MAGISK_APK" | sha256sum -c - >/dev/null

rm -rf "$MAGISK_EXTRACT"
mkdir -p "$MAGISK_EXTRACT"
unzip -o "$MAGISK_APK" \
  'lib/arm64-v8a/libbusybox.so' \
  'lib/arm64-v8a/libmagiskboot.so' \
  'lib/arm64-v8a/libmagiskpolicy.so' \
  -d "$MAGISK_EXTRACT" >/dev/null

SRC="$PACKAGE_OUT/anykernel-src"
ZIP_PATH="$PACKAGE_OUT/$RELEASE_ZIP_NAME"
rm -rf "$SRC" "$ZIP_PATH"
mkdir -p "$SRC"
cp -a "$AK3_CACHE"/. "$SRC"/
rm -rf "$SRC/.git" "$SRC/.github" "$SRC/README.md"
rm -f "$SRC"/Image* "$SRC"/zImage* "$SRC"/dtb "$SRC"/*.img
cp -f "$IMAGE" "$SRC/Image"
cp -f "$RELEASE_ROOT/templates/anykernel/anykernel.sh.in" "$SRC/anykernel.sh"
cp -f "$MAGISK_EXTRACT/lib/arm64-v8a/libbusybox.so" "$SRC/tools/busybox"
cp -f "$MAGISK_EXTRACT/lib/arm64-v8a/libmagiskboot.so" "$SRC/tools/magiskboot"
cp -f "$MAGISK_EXTRACT/lib/arm64-v8a/libmagiskpolicy.so" "$SRC/tools/magiskpolicy"
chmod 755 "$SRC/tools/busybox" "$SRC/tools/magiskboot" "$SRC/tools/magiskpolicy" "$SRC/META-INF/com/google/android/update-binary"

(
  cd "$SRC"
  zip -r9 "$ZIP_PATH" . \
    -x './.git/*' './README.md' './*placeholder' './ramdisk/placeholder' './patch/placeholder' >/dev/null
)

unzip -t "$ZIP_PATH" >/dev/null
zip_listing="$(unzip -l "$ZIP_PATH")"
for needed in 'META-INF/com/google/android/update-binary' 'tools/ak3-core.sh' 'tools/busybox' 'tools/magiskboot' 'anykernel.sh' 'Image'; do
  grep -Fq "$needed" <<<"$zip_listing" || { echo "zip missing $needed" >&2; exit 1; }
done
if grep -Eq 'placeholder|boot\.img|arm32-backup' <<<"$zip_listing"; then
  echo 'zip unexpectedly contains placeholder, boot.img, or arm32 backup' >&2
  exit 1
fi
if ! file "$SRC/tools/busybox" "$SRC/tools/magiskboot" | rg -q 'ARM aarch64'; then
  echo 'AnyKernel3 tools are not arm64.' >&2
  file "$SRC/tools/busybox" "$SRC/tools/magiskboot" >&2
  exit 1
fi
image_kernel_string="$(strings -a "$SRC/Image" | rg -F -m 1 "Linux version $KERNEL_RELEASE" || true)"
if [[ -z "$image_kernel_string" ]]; then
  echo "Packaged Image does not contain expected release string: $KERNEL_RELEASE" >&2
  exit 1
fi

cp -f "$BOOT_IMG" "$PACKAGE_OUT/boot-96m-fastboot-test.img"
[[ -f "$DIST/boot-avb-info.txt" ]] && cp -f "$DIST/boot-avb-info.txt" "$PACKAGE_OUT/boot-96m-avb-info.txt"
(
  cd "$PACKAGE_OUT"
  sha256sum "$RELEASE_ZIP_NAME" boot-96m-fastboot-test.img anykernel-src/Image anykernel-src/tools/busybox anykernel-src/tools/magiskboot > SHA256SUMS
)

printf 'Packaged AnyKernel3 zip:\n%s\n' "$ZIP_PATH"
stat -c '%n %s bytes' "$ZIP_PATH" "$PACKAGE_OUT/boot-96m-fastboot-test.img"
cat "$PACKAGE_OUT/SHA256SUMS"
