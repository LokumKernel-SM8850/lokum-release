#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/../common.sh"

require_command git

KERNELSU_NEXT_UPSTREAM_REPO="${KERNELSU_NEXT_UPSTREAM_REPO:-https://github.com/KernelSU-Next/KernelSU-Next.git}"
KERNELSU_NEXT_TRACK_REF="${KERNELSU_NEXT_TRACK_REF:-refs/heads/dev}"
SUSFS_UPSTREAM_REPO="${SUSFS_UPSTREAM_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_TRACK_REF="${SUSFS_TRACK_REF:-refs/heads/gki-android16-6.12}"

ls_remote_sha() {
  local repo="$1" ref="$2" sha
  sha="$(git ls-remote "$repo" "$ref" | awk 'NR == 1 {print $1}')"
  if [[ -z "$sha" ]]; then
    echo "Could not resolve $ref from $repo" >&2
    exit 1
  fi
  printf '%s\n' "$sha"
}

ksu_latest="$(ls_remote_sha "$KERNELSU_NEXT_UPSTREAM_REPO" "$KERNELSU_NEXT_TRACK_REF")"
susfs_latest="$(ls_remote_sha "$SUSFS_UPSTREAM_REPO" "$SUSFS_TRACK_REF")"

ksu_pinned="${KERNELSU_NEXT_BASE_CANDIDATE:-${KERNELSU_NEXT_HEAD:-}}"
susfs_pinned="${SUSFS_SOURCE_HEAD:-}"

cat <<STATUS
KERNELSU_NEXT_UPSTREAM_REPO=$KERNELSU_NEXT_UPSTREAM_REPO
KERNELSU_NEXT_TRACK_REF=$KERNELSU_NEXT_TRACK_REF
KERNELSU_NEXT_PINNED=$ksu_pinned
KERNELSU_NEXT_LATEST=$ksu_latest
KERNELSU_NEXT_UPDATE=$([[ "$ksu_latest" != "$ksu_pinned" ]] && echo true || echo false)
SUSFS_UPSTREAM_REPO=$SUSFS_UPSTREAM_REPO
SUSFS_TRACK_REF=$SUSFS_TRACK_REF
SUSFS_PINNED=$susfs_pinned
SUSFS_LATEST=$susfs_latest
SUSFS_UPDATE=$([[ "$susfs_latest" != "$susfs_pinned" ]] && echo true || echo false)
STATUS
