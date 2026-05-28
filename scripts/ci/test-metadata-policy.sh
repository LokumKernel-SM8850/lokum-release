#!/usr/bin/env bash
set -euo pipefail

RELEASE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fail=0

expect_line() {
  local file="$1" expected="$2"
  if ! grep -Fxq "$expected" "$file"; then
    echo "missing in ${file#$RELEASE_ROOT/}: $expected" >&2
    fail=1
  fi
}

expect_line "$RELEASE_ROOT/manifests/pandora-os3.0.309.env" 'KERNEL_COMMON_BRANCH="6.12.23-android16-5-lokumkernel-ksun-susfs-rc1"'
expect_line "$RELEASE_ROOT/manifests/pandora-os3.0.309.env" 'RELEASE_ID="lokumkernel-xiaomi17pro-6.12.23-ksun-susfs-rc1"'
expect_line "$RELEASE_ROOT/manifests/pandora-os3.0.309.env" 'RELEASE_ZIP_NAME="LokumKernel-Xiaomi17Pro-6.12.23-KSun-SUSFS-rc1.zip"'
expect_line "$RELEASE_ROOT/manifests/pandora-os3.0.309-android16-6.12.38-exp.env" 'KERNEL_COMMON_BRANCH="6.12.38-android16-5-lokumkernel-ksun-susfs-exp1"'
expect_line "$RELEASE_ROOT/manifests/pandora-os3.0.309-android16-6.12.38-exp.env" 'KERNEL_COMMON_HEAD="4131670aae805c1f361a1c8bc15dd3e58ad492a7"'
expect_line "$RELEASE_ROOT/manifests/pandora-os3.0.309-android16-6.12.38-exp.env" 'RELEASE_ID="lokumkernel-xiaomi17pro-6.12.38-ksun-susfs-exp1"'
expect_line "$RELEASE_ROOT/manifests/pandora-os3.0.309-android16-6.12.38-exp.env" 'RELEASE_ZIP_NAME="LokumKernel-Xiaomi17Pro-6.12.38-KSun-SUSFS-exp1.zip"'

if rg -n 'ksunext|KernelSUNext|pandora-6\.12\.23-ksun|android16-6\.12-2025-09-ksun|pandora-os3\.0\.309-lokumkernel|LokumKernel-pandora' \
  "$RELEASE_ROOT/manifests" "$RELEASE_ROOT/docs" >/tmp/lokum-old-metadata-names.txt; then
  echo "old naming still present:" >&2
  cat /tmp/lokum-old-metadata-names.txt >&2
  fail=1
fi

source_date_epoch="$(env -u SOURCE_DATE_EPOCH MANIFEST="$RELEASE_ROOT/manifests/pandora-os3.0.309.env" bash -c 'source "$0/scripts/common.sh"; printf "%s" "$SOURCE_DATE_EPOCH"' "$RELEASE_ROOT")"
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]] || (( source_date_epoch < 1700000000 )); then
  echo "SOURCE_DATE_EPOCH default is not a real timestamp: $source_date_epoch" >&2
  fail=1
fi

exit "$fail"
