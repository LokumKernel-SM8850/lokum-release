#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command realpath

if [[ ! -d "$COMMON_REPO" ]]; then
  echo "kernel_platform/common is missing: $COMMON_REPO" >&2
  exit 1
fi

if [[ ! -x "$KERNEL_PLATFORM/tools/bazel" ]]; then
  echo "Kleaf Bazel wrapper is missing or not executable: $KERNEL_PLATFORM/tools/bazel" >&2
  exit 1
fi

mkdir -p "$DIST" "$BAZEL_OUTPUT_USER_ROOT"

if [[ ! -e "$KERNEL_PLATFORM/build/msm_kernel_extensions.bzl" \
    && -f "$KERNEL_PLATFORM/soc-repo/kleaf-scripts/msm_kernel_extensions.bzl" ]]; then
  ln -s ../soc-repo/kleaf-scripts/msm_kernel_extensions.bzl \
    "$KERNEL_PLATFORM/build/msm_kernel_extensions.bzl"
fi

if [[ ! -e "$KERNEL_PLATFORM/build/abl_extensions.bzl" \
    && -f "$KERNEL_PLATFORM/bootable/bootloader/edk2/abl_extensions.bzl" ]]; then
  ln -s ../bootable/bootloader/edk2/abl_extensions.bzl \
    "$KERNEL_PLATFORM/build/abl_extensions.bzl"
fi

print_release_context
printf 'Building target: %s\n' "$KLEAF_TARGET"

repo_manifest_args=()
if [[ -f "$REPO_MANIFEST" ]]; then
  repo_manifest_args=(--repo_manifest="$(realpath "$REPO_ROOT"):$(realpath "$REPO_MANIFEST")")
fi

cd "$KERNEL_PLATFORM"
env BAZEL_OUTPUT_USER_ROOT="$BAZEL_OUTPUT_USER_ROOT" \
  SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
  tools/bazel run --config=stamp "${repo_manifest_args[@]}" "$KLEAF_TARGET" -- --destdir="$DIST"

printf 'Build artifacts in %s:\n' "$DIST"
find "$DIST" -maxdepth 1 -type f -printf '%f %s bytes\n' | sort
