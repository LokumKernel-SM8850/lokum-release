#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="${MANIFEST:-$RELEASE_ROOT/manifests/pandora-os3.0.309-android16-6.12.38-exp.env}"
# shellcheck source=../common.sh
source "$RELEASE_ROOT/scripts/common.sh"

require_command git
require_command gh
require_command python3
require_command sha256sum

SOURCE_BRANCH="${SOURCE_BRANCH:-${KERNEL_COMMON_BRANCH:-android16-6.12-2025-09-ksunext-susfs}}"
PUBLISH_RELEASE="${PUBLISH_RELEASE:-true}"
FORCE_BUILD="${FORCE_BUILD:-false}"
UPDATE_KSUNEXT="${UPDATE_KSUNEXT:-true}"
UPDATE_SUSFS="${UPDATE_SUSFS:-true}"
PUSH_SOURCE_BRANCH="${PUSH_SOURCE_BRANCH:-true}"
RELEASE_SUFFIX="${RELEASE_SUFFIX:-auto-$(date -u +%Y%m%d-%H%M)}"
KERNELSU_NEXT_UPSTREAM_REPO="${KERNELSU_NEXT_UPSTREAM_REPO:-https://github.com/KernelSU-Next/KernelSU-Next.git}"
KERNELSU_NEXT_TRACK_REF="${KERNELSU_NEXT_TRACK_REF:-refs/heads/dev}"
SUSFS_UPSTREAM_REPO="${SUSFS_UPSTREAM_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_TRACK_REF="${SUSFS_TRACK_REF:-refs/heads/gki-android16-6.12}"
KERNELSU_NEXT_SUSFS_PATCH_COMMIT="${KERNELSU_NEXT_SUSFS_PATCH_COMMIT:-${KERNELSU_NEXT_HEAD:-}}"
KERNELSU_NEXT_LOKUM_REMOTE="${KERNELSU_NEXT_LOKUM_REMOTE:-git@github.com:LokumKernel-SM8850/kernelsu-next.git}"
KERNELSU_NEXT_LOKUM_BRANCH="${KERNELSU_NEXT_LOKUM_BRANCH:-}"
PUSH_KSUNEXT_BRANCH="${PUSH_KSUNEXT_BRANCH:-true}"

bool_true() { [[ "${1,,}" == "true" || "$1" == "1" || "${1,,}" == "yes" ]]; }
ls_remote_sha() {
  local repo="$1" ref="$2" sha
  sha="$(git ls-remote "$repo" "$ref" | awk 'NR == 1 {print $1}')"
  if [[ -z "$sha" ]]; then
    echo "Could not resolve $ref from $repo" >&2
    exit 1
  fi
  printf '%s\n' "$sha"
}
ensure_clean_repo() {
  local repo="$1" name="$2"
  if ! git -C "$repo" diff --quiet || ! git -C "$repo" diff --cached --quiet; then
    echo "$name repo is dirty; refusing CI mutation:" >&2
    git -C "$repo" status --short >&2
    exit 1
  fi
}

ksu_latest="$(ls_remote_sha "$KERNELSU_NEXT_UPSTREAM_REPO" "$KERNELSU_NEXT_TRACK_REF")"
susfs_latest="$(ls_remote_sha "$SUSFS_UPSTREAM_REPO" "$SUSFS_TRACK_REF")"
ksu_pinned="${KERNELSU_NEXT_BASE_CANDIDATE:-${KERNELSU_NEXT_HEAD:-}}"
susfs_pinned="${SUSFS_SOURCE_HEAD:-}"
ksu_changed=false
susfs_changed=false
[[ "$ksu_latest" != "$ksu_pinned" ]] && ksu_changed=true
[[ "$susfs_latest" != "$susfs_pinned" ]] && susfs_changed=true

printf 'KernelSU Next pinned=%s latest=%s update=%s\n' "$ksu_pinned" "$ksu_latest" "$ksu_changed"
printf 'SUSFS pinned=%s latest=%s update=%s\n' "$susfs_pinned" "$susfs_latest" "$susfs_changed"

if ! bool_true "$FORCE_BUILD" && [[ "$ksu_changed" != true && "$susfs_changed" != true ]]; then
  echo "No upstream update detected and FORCE_BUILD=false; nothing to build."
  exit 0
fi

if [[ ! -d "$KERNELSU_NEXT_REPO/.git" ]]; then
  mkdir -p "$(dirname "$KERNELSU_NEXT_REPO")"
  git clone "$KERNELSU_NEXT_UPSTREAM_REPO" "$KERNELSU_NEXT_REPO"
fi
if ! git -C "$KERNELSU_NEXT_REPO" remote get-url lokum >/dev/null 2>&1; then
  git -C "$KERNELSU_NEXT_REPO" remote add lokum "$KERNELSU_NEXT_LOKUM_REMOTE"
fi
if ! git -C "$KERNELSU_NEXT_REPO" remote get-url origin >/dev/null 2>&1; then
  git -C "$KERNELSU_NEXT_REPO" remote add origin "$KERNELSU_NEXT_UPSTREAM_REPO"
fi

ensure_clean_repo "$COMMON_REPO" common
ensure_clean_repo "$KERNELSU_NEXT_REPO" KernelSU-Next
if [[ -d "$KERNEL_PLATFORM/susfs4ksu/.git" ]]; then
  ensure_clean_repo "$KERNEL_PLATFORM/susfs4ksu" susfs4ksu
fi

printf 'Checking out common source branch %s from %s\n' "$SOURCE_BRANCH" "$KERNEL_REPO_REMOTE"
git -C "$COMMON_REPO" fetch "$KERNEL_REPO_REMOTE" "$SOURCE_BRANCH:refs/remotes/lokum/$SOURCE_BRANCH" --force
git -C "$COMMON_REPO" checkout -B "ci/${SOURCE_BRANCH//\//-}" "refs/remotes/lokum/$SOURCE_BRANCH"

actual_ksu_head="$KERNELSU_NEXT_HEAD"
if bool_true "$UPDATE_KSUNEXT" && [[ "$ksu_changed" == true ]]; then
  if [[ -z "$KERNELSU_NEXT_SUSFS_PATCH_COMMIT" ]]; then
    echo "KERNELSU_NEXT_SUSFS_PATCH_COMMIT/KERNELSU_NEXT_HEAD is required to replay Lokum SUSFS integration." >&2
    exit 1
  fi
  git -C "$KERNELSU_NEXT_REPO" fetch origin "$KERNELSU_NEXT_TRACK_REF"
  git -C "$KERNELSU_NEXT_REPO" checkout -B "ci/lokum-ksunext-${ksu_latest:0:12}" "$ksu_latest"
  git -C "$KERNELSU_NEXT_REPO" cherry-pick "$KERNELSU_NEXT_SUSFS_PATCH_COMMIT"
  actual_ksu_head="$(git -C "$KERNELSU_NEXT_REPO" rev-parse HEAD)"
  if bool_true "$PUSH_KSUNEXT_BRANCH"; then
    ksu_branch="lokum/dev-susfs-${ksu_latest:0:8}"
    git -C "$KERNELSU_NEXT_REPO" push lokum "HEAD:$ksu_branch" --force-with-lease
    KERNELSU_NEXT_LOKUM_BRANCH="$ksu_branch"
  fi
else
  if [[ -n "$KERNELSU_NEXT_LOKUM_BRANCH" ]]; then
    git -C "$KERNELSU_NEXT_REPO" fetch lokum "$KERNELSU_NEXT_LOKUM_BRANCH"
  fi
  git -C "$KERNELSU_NEXT_REPO" checkout --detach "$KERNELSU_NEXT_HEAD"
  actual_ksu_head="$(git -C "$KERNELSU_NEXT_REPO" rev-parse HEAD)"
fi

actual_susfs_head="$SUSFS_SOURCE_HEAD"
if bool_true "$UPDATE_SUSFS" && [[ "$susfs_changed" == true ]]; then
  susfs_repo="$KERNEL_PLATFORM/susfs4ksu"
  if [[ ! -d "$susfs_repo/.git" ]]; then
    git clone "$SUSFS_UPSTREAM_REPO" "$susfs_repo"
  fi
  git -C "$susfs_repo" fetch origin "$SUSFS_TRACK_REF"
  git -C "$susfs_repo" checkout --detach "$susfs_latest"
  MANIFEST="$MANIFEST" WORKSPACE_ROOT="$WORKSPACE_ROOT" "$SCRIPT_DIR/apply-susfs-update.sh" "$susfs_repo"
  actual_susfs_head="$(git -C "$susfs_repo" rev-parse HEAD)"
else
  if [[ -d "$KERNEL_PLATFORM/susfs4ksu/.git" && -n "$SUSFS_SOURCE_HEAD" ]]; then
    git -C "$KERNEL_PLATFORM/susfs4ksu" checkout --detach "$SUSFS_SOURCE_HEAD"
    actual_susfs_head="$(git -C "$KERNEL_PLATFORM/susfs4ksu" rev-parse HEAD)"
  fi
fi

actual_common_head="$(git -C "$COMMON_REPO" rev-parse HEAD)"
source_branch_for_release="$SOURCE_BRANCH"
if bool_true "$PUSH_SOURCE_BRANCH"; then
  auto_source_branch="${SOURCE_BRANCH}-auto-${RELEASE_SUFFIX}"
  git -C "$COMMON_REPO" branch -f "$auto_source_branch" HEAD
  git -C "$COMMON_REPO" push "$KERNEL_REPO_REMOTE" "$auto_source_branch" --force-with-lease
  source_branch_for_release="$auto_source_branch"
fi

short_ksu="${actual_ksu_head:0:7}"
short_susfs="${actual_susfs_head:0:7}"
ci_release_id="${RELEASE_ID}-${RELEASE_SUFFIX}-ksu${short_ksu}-susfs${short_susfs}"
ci_zip_name="${RELEASE_ZIP_NAME%.zip}-${RELEASE_SUFFIX}-ksu${short_ksu}-susfs${short_susfs}.zip"
ci_manifest="${RUNNER_TEMP:-$RELEASE_ROOT/out}/lokum-ci-manifest-${RELEASE_SUFFIX}.env"
mkdir -p "$(dirname "$ci_manifest")"
cp "$MANIFEST" "$ci_manifest"
python3 - "$ci_manifest" \
  "KERNEL_COMMON_BRANCH=$source_branch_for_release" \
  "KERNEL_COMMON_HEAD=$actual_common_head" \
  "KERNELSU_NEXT_HEAD=$actual_ksu_head" \
  "KERNELSU_NEXT_BASE_CANDIDATE=$ksu_latest" \
  "KERNELSU_NEXT_LOKUM_BRANCH=$KERNELSU_NEXT_LOKUM_BRANCH" \
  "SUSFS_SOURCE_HEAD=$actual_susfs_head" \
  "RELEASE_ID=$ci_release_id" \
  "RELEASE_ZIP_NAME=$ci_zip_name" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
updates = dict(arg.split('=', 1) for arg in sys.argv[2:])
lines = path.read_text().splitlines()
seen = set()
out = []
for line in lines:
    stripped = line.strip()
    if '=' in stripped and not stripped.startswith('#'):
        key = stripped.split('=', 1)[0]
        if key in updates:
            out.append(f'{key}="{updates[key]}"')
            seen.add(key)
            continue
    out.append(line)
for key, value in updates.items():
    if key not in seen:
        out.append(f'{key}="{value}"')
path.write_text('\n'.join(out) + '\n')
PY

printf 'CI manifest: %s\n' "$ci_manifest"
MANIFEST="$ci_manifest" WORKSPACE_ROOT="$WORKSPACE_ROOT" "$RELEASE_ROOT/scripts/release.sh"

out_root="$RELEASE_ROOT/out/$ci_release_id"
package_out="$out_root/package"
notes="$out_root/release-notes.md"
cat >> "$notes" <<NOTES_EOF

## CI source state

- Source branch: \`$source_branch_for_release\`
- Common head: \`$actual_common_head\`
- KernelSU Next integration head: \`$actual_ksu_head\`
- KernelSU Next upstream tracked head: \`$ksu_latest\`
- SUSFS source head: \`$actual_susfs_head\`
- SUSFS upstream tracked head: \`$susfs_latest\`

This release was produced by the self-hosted LokumKernel CI lane. It is a pre-release until a real device passes the fastboot boot runtime checklist.
NOTES_EOF

(
  cd "$package_out"
  sha256sum -c SHA256SUMS
)

if bool_true "$PUBLISH_RELEASE"; then
  if gh release view "$ci_release_id" --repo LokumKernel-SM8850/lokum-release >/dev/null 2>&1; then
    echo "Release already exists: $ci_release_id" >&2
    exit 1
  fi
  gh release create "$ci_release_id" \
    --repo LokumKernel-SM8850/lokum-release \
    --target main \
    --title "LokumKernel SM8850 auto ${KERNEL_RELEASE} KernelSU Next + SUSFS" \
    --notes-file "$notes" \
    --prerelease \
    "$package_out/$ci_zip_name" \
    "$package_out/boot-96m-fastboot-test.img" \
    "$package_out/boot-96m-avb-info.txt" \
    "$package_out/SHA256SUMS"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "release_id=$ci_release_id"
    echo "package_out=$package_out"
    echo "zip_name=$ci_zip_name"
    echo "published=$PUBLISH_RELEASE"
  } >> "$GITHUB_OUTPUT"
fi

printf 'CI release output ready: %s\n' "$out_root"
