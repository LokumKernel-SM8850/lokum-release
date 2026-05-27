#!/usr/bin/env bash
set -euo pipefail
fragment="${1:-arch/arm64/configs/xiaomi_sm8850_bootimg.fragment}"
if [[ ! -f "$fragment" ]]; then
  echo "Config fragment not found: $fragment" >&2
  exit 1
fi
ensure_line() {
  local line="$1" key="${line%%=*}"
  if grep -Eq "^# ${key} is not set$|^${key}=" "$fragment"; then
    sed -i -E "s|^# ${key} is not set$|$line|; s|^${key}=.*$|$line|" "$fragment"
  else
    printf '%s\n' "$line" >> "$fragment"
  fi
}
ensure_line 'CONFIG_KSU=y'
ensure_line 'CONFIG_KSU_SUSFS=y'
ensure_line 'CONFIG_KSU_SUSFS_SUS_PATH=y'
ensure_line 'CONFIG_KSU_SUSFS_SUS_MOUNT=y'
ensure_line 'CONFIG_KSU_SUSFS_SUS_KSTAT=y'
ensure_line 'CONFIG_KSU_SUSFS_TRY_UMOUNT=y'
ensure_line 'CONFIG_KSU_SUSFS_SPOOF_UNAME=y'
ensure_line 'CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y'
ensure_line 'CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y'
ensure_line 'CONFIG_KSU_SUSFS_OPEN_REDIRECT=y'
ensure_line 'CONFIG_KSU_SUSFS_SUS_MAP=y'
ensure_line 'CONFIG_KSU_SUSFS_ENABLE_LOG=y'
