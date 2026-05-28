#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command od
require_command strings
require_command rg
require_command sha256sum
require_command stat

BOOT_IMG="$DIST/boot.img"
STOCK_BOOT_IMG="${STOCK_BOOT_IMG:-$WORKSPACE_ROOT/stock_refs/pandora_eu_OS3.0.309.0.WBLCNXM/images/boot.img}"
FALLBACK_STOCK_BOOT_IMG="$HOME/Downloads/309/images/boot.img"
EXPECTED_BOOT_SIZE="${EXPECTED_BOOT_SIZE:-$BOOT_IMAGE_SIZE}"

if [[ ! -f "$BOOT_IMG" ]]; then
  echo "Built boot.img not found: $BOOT_IMG" >&2
  exit 1
fi

if [[ ! -f "$STOCK_BOOT_IMG" && -f "$FALLBACK_STOCK_BOOT_IMG" ]]; then
  STOCK_BOOT_IMG="$FALLBACK_STOCK_BOOT_IMG"
fi

magic="$(od -An -tx1 -N 8 "$BOOT_IMG" | tr -d ' \n')"
if [[ "$magic" != "414e44524f494421" ]]; then
  echo "boot.img does not start with Android boot magic." >&2
  exit 1
fi

kernel_string="$(strings -a "$BOOT_IMG" | rg -F -m 1 "Linux version $KERNEL_RELEASE" || true)"
if [[ -z "$kernel_string" ]]; then
  echo "Could not find expected LokumKernel Linux version string in built boot.img: $KERNEL_RELEASE" >&2
  exit 1
fi

config_file=""
while IFS= read -r candidate_config; do
  config_file="$candidate_config"
  break
done < <(
  find "$DIST" -maxdepth 1 -type f \
    \( -name '*_dot_config' -o -name '*.config' -o -name '.config' \) \
    | sort
)

if [[ -n "$config_file" ]]; then
  if ! grep -Fxq "CONFIG_LOCALVERSION=\"$KERNEL_LOCALVERSION\"" "$config_file"; then
    echo "Kernel .config does not set expected CONFIG_LOCALVERSION: $config_file" >&2
    exit 1
  fi
  if ! grep -Fxq '# CONFIG_LOCALVERSION_AUTO is not set' "$config_file"; then
    echo "Kernel .config still has CONFIG_LOCALVERSION_AUTO enabled: $config_file" >&2
    exit 1
  fi
  if grep -q '^CONFIG_KSU_SUSFS_DEFAULT_UNAME_RELEASE=' "$config_file"; then
    echo "Old SUSFS uname spoof config is still present in .config: $config_file" >&2
    exit 1
  fi
  required_configs=(
    CONFIG_KSU=y
    CONFIG_KSU_SUSFS=y
    CONFIG_KSU_SUSFS_SUS_PATH=y
    CONFIG_KSU_SUSFS_SUS_MOUNT=y
    CONFIG_KSU_SUSFS_SUS_KSTAT=y
    CONFIG_KSU_SUSFS_SPOOF_UNAME=y
    CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
    CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
    CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
    CONFIG_KSU_SUSFS_SUS_MAP=y
  )
  if [[ -n "${EXTRA_REQUIRED_CONFIGS:-}" ]]; then
    # shellcheck disable=SC2206
    extra_required_configs=($EXTRA_REQUIRED_CONFIGS)
    required_configs+=("${extra_required_configs[@]}")
  fi
  for required in "${required_configs[@]}"; do
    if ! grep -Fxq "$required" "$config_file"; then
      echo "Kernel .config missing required option: $required" >&2
      exit 1
    fi
  done
fi

module_file="$(find "$DIST" -maxdepth 1 -type f -name '*.ko' | sort | head -n 1 || true)"
if [[ -n "$module_file" ]]; then
  module_vermagic="$(strings -a "$module_file" | rg -m 1 '^vermagic=' || true)"
  if [[ "$module_vermagic" != "vermagic=$KERNEL_RELEASE "* ]]; then
    echo "Built module vermagic does not use expected release: $module_file" >&2
    printf '%s\n' "$module_vermagic" >&2
    exit 1
  fi
fi

if [[ -f "$STOCK_BOOT_IMG" ]]; then
  EXPECTED_BOOT_SIZE="$(stat -c%s "$STOCK_BOOT_IMG")"
fi

built_size="$(stat -c%s "$BOOT_IMG")"
if (( built_size != EXPECTED_BOOT_SIZE )); then
  echo "Built boot.img size does not match expected Xiaomi boot size ($built_size != $EXPECTED_BOOT_SIZE)." >&2
  [[ -f "$STOCK_BOOT_IMG" ]] && echo "Reference stock boot.img: $STOCK_BOOT_IMG" >&2
  exit 1
fi

if [[ -x "$AVBTOOL" ]]; then
  avb_info="$DIST/boot-avb-info.txt"
  python3 "$AVBTOOL" info_image --image "$BOOT_IMG" > "$avb_info"
  if ! grep -Fq "Image size:               $EXPECTED_BOOT_SIZE bytes" "$avb_info"; then
    echo "AVB footer does not report expected image size: $EXPECTED_BOOT_SIZE" >&2
    cat "$avb_info" >&2
    exit 1
  fi
  if ! rg -q '^      Partition Name:\s+boot$' "$avb_info"; then
    echo "AVB footer does not use partition_name=boot." >&2
    cat "$avb_info" >&2
    exit 1
  fi
fi

sha256sum "$BOOT_IMG" > "$DIST/boot.img.sha256"
printf '%s\n' "$kernel_string" > "$DIST/boot-kernel-string.txt"

printf 'Verified boot.img:\n'
stat -c '%n %s bytes' "$BOOT_IMG"
cat "$DIST/boot.img.sha256"
cat "$DIST/boot-kernel-string.txt"
if [[ -f "${avb_info:-}" ]]; then
  rg -n "Image size|Original image size|Algorithm|Rollback Index|Partition Name" "$avb_info" || true
fi
