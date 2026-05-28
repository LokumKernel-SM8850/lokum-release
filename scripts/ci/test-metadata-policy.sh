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

expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.23-ksun-susfs-rc1.env" 'KERNEL_COMMON_BRANCH="6.12.23-android16-5-lokumkernel-ksun-susfs-rc1"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.23-ksun-susfs-rc1.env" 'DEVICE_CODENAME="sm8850"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.23-ksun-susfs-rc1.env" 'DEVICE_MARKETING_NAME="Xiaomi 17 Series"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.23-ksun-susfs-rc1.env" 'SUPPORTED_CODENAMES="pudding pandora popsicle nezha"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.23-ksun-susfs-rc1.env" 'RUNTIME_TESTED_CODENAMES="pandora"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.23-ksun-susfs-rc1.env" 'RELEASE_ID="lokumkernel-sm8850-6.12.23-ksun-susfs-rc1"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.23-ksun-susfs-rc1.env" 'RELEASE_ZIP_NAME="LokumKernel-SM8850-6.12.23-KSun-SUSFS-rc1.zip"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-ksun-susfs-exp1.env" 'KERNEL_COMMON_BRANCH="6.12.38-android16-5-lokumkernel-ksun-susfs-exp1"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-ksun-susfs-exp1.env" 'KERNEL_COMMON_HEAD="4131670aae805c1f361a1c8bc15dd3e58ad492a7"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-ksun-susfs-exp1.env" 'DEVICE_CODENAME="sm8850"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-ksun-susfs-exp1.env" 'DEVICE_MARKETING_NAME="Xiaomi 17 Series"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-ksun-susfs-exp1.env" 'SUPPORTED_CODENAMES="pudding pandora popsicle nezha"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-ksun-susfs-exp1.env" 'RUNTIME_TESTED_CODENAMES="pandora"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-ksun-susfs-exp1.env" 'RELEASE_ID="lokumkernel-sm8850-6.12.38-ksun-susfs-exp1"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-ksun-susfs-exp1.env" 'RELEASE_ZIP_NAME="LokumKernel-SM8850-6.12.38-KSun-SUSFS-exp1.zip"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-droidspaces-exp.env" 'KERNEL_RELEASE="6.12.38-android16-5-LokumKernel-Droidspaces"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-droidspaces-exp.env" 'KERNEL_COMMON_BRANCH="6.12.38-android16-5-lokumkernel-ksun-susfs-droidspaces-exp1"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-droidspaces-exp.env" 'KERNEL_COMMON_HEAD="a71ebf3075382bd5b083ab332d756a758e97a3c4"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-droidspaces-exp.env" 'DEVICE_CODENAME="sm8850"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-droidspaces-exp.env" 'DEVICE_MARKETING_NAME="Xiaomi 17 Series"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-droidspaces-exp.env" 'SUPPORTED_CODENAMES="pudding pandora popsicle nezha"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-droidspaces-exp.env" 'RUNTIME_TESTED_CODENAMES="pandora"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-droidspaces-exp.env" 'RELEASE_ID="lokumkernel-sm8850-6.12.38-ksun-susfs-droidspaces-exp1"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-droidspaces-exp.env" 'RELEASE_ZIP_NAME="LokumKernel-SM8850-6.12.38-KSun-SUSFS-Droidspaces-exp1.zip"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-droidspaces-exp.env" 'FEATURE_LABEL="KSun + SUSFS v2.1.0 + Droidspaces"'
expect_line "$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-droidspaces-exp.env" 'RELEASE_TITLE="LokumKernel 6.12.38 Droidspaces exp1"'

expect_line "$RELEASE_ROOT/templates/anykernel/anykernel.sh.in" 'device.name1=pudding'
expect_line "$RELEASE_ROOT/templates/anykernel/anykernel.sh.in" 'device.name2=pandora'
expect_line "$RELEASE_ROOT/templates/anykernel/anykernel.sh.in" 'device.name3=popsicle'
expect_line "$RELEASE_ROOT/templates/anykernel/anykernel.sh.in" 'device.name4=nezha'
expect_line "$RELEASE_ROOT/templates/anykernel/anykernel.sh.in" 'device.name5='
expect_line "$RELEASE_ROOT/templates/anykernel/anykernel.sh.in" 'kernel.string=Lokum Kernel Xiaomi 17 series by MetoisTaken'

if [[ -e "$RELEASE_ROOT/manifests/pandora-os3.0.309-android16-6.12.38-exp.env" ]]; then
  echo "old pandora-only 6.12.38 manifest must be replaced by the common SM8850 manifest" >&2
  fail=1
fi

if rg -n 'ksunext|KernelSUNext|pandora-6\.12\.23-ksun|android16-6\.12-2025-09-ksun|pandora-os3\.0\.309-lokumkernel|LokumKernel-pandora|lokumkernel-xiaomi17pro-6\.12\.23-ksun-susfs|LokumKernel-Xiaomi17Pro-6\.12\.23|pandora-os3\.0\.309-android16-6\.12\.38|lokumkernel-xiaomi17pro-6\.12\.38|LokumKernel-Xiaomi17Pro-6\.12\.38' \
  "$RELEASE_ROOT/manifests" "$RELEASE_ROOT/docs" >/tmp/lokum-old-metadata-names.txt; then
  echo "old naming still present:" >&2
  cat /tmp/lokum-old-metadata-names.txt >&2
  fail=1
fi

source_date_epoch="$(env -u SOURCE_DATE_EPOCH MANIFEST="$RELEASE_ROOT/manifests/sm8850-android16-6.12.23-ksun-susfs-rc1.env" bash -c 'source "$0/scripts/common.sh"; printf "%s" "$SOURCE_DATE_EPOCH"' "$RELEASE_ROOT")"
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]] || (( source_date_epoch < 1700000000 )); then
  echo "SOURCE_DATE_EPOCH default is not a real timestamp: $source_date_epoch" >&2
  fail=1
fi

exit "$fail"
