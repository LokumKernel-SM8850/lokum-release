#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="${MANIFEST:-$RELEASE_ROOT/manifests/pandora-os3.0.309.env}"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$MANIFEST"

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$RELEASE_ROOT/../.." && pwd)}"
KERNEL_PLATFORM="${KERNEL_PLATFORM:-$WORKSPACE_ROOT/kernel_platform}"
COMMON_REPO="${COMMON_REPO:-$KERNEL_PLATFORM/common}"
KERNELSU_NEXT_REPO="${KERNELSU_NEXT_REPO:-$KERNEL_PLATFORM/KernelSU-Next}"
CACHE_DIR="${CACHE_DIR:-$RELEASE_ROOT/.cache}"
OUT_ROOT="${OUT_ROOT:-$RELEASE_ROOT/out/$RELEASE_ID}"
DIST="${DIST:-$OUT_ROOT/dist}"
PACKAGE_OUT="${PACKAGE_OUT:-$OUT_ROOT/package}"
BAZEL_OUTPUT_USER_ROOT="${BAZEL_OUTPUT_USER_ROOT:-$WORKSPACE_ROOT/.bazel-output-user-root}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}"
REPO_ROOT="${REPO_ROOT:-$WORKSPACE_ROOT}"
REPO_MANIFEST="${REPO_MANIFEST:-$WORKSPACE_ROOT/.repo/manifests/default.xml}"
AVBTOOL="${AVBTOOL:-$KERNEL_PLATFORM/external/avb/avbtool.py}"

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command missing: $cmd" >&2
    exit 1
  fi
}

print_release_context() {
  cat <<CTX
Project:        $PROJECT_NAME
Device:         $DEVICE_CODENAME ($DEVICE_MARKETING_NAME)
Firmware:       $FIRMWARE_ID / Android $ANDROID_VERSION
Kernel release: $KERNEL_RELEASE
Workspace:      $WORKSPACE_ROOT
Kernel platform:$KERNEL_PLATFORM
Dist:           $DIST
Package out:    $PACKAGE_OUT
CTX
}
