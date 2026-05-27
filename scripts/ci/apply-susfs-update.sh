#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common.sh
source "$SCRIPT_DIR/../common.sh"

susfs_repo="${1:-$KERNEL_PLATFORM/susfs4ksu}"
patch_file="$susfs_repo/kernel_patches/50_add_susfs_in_gki-android16-6.12.patch"

if [[ ! -f "$patch_file" ]]; then
  echo "SUSFS GKI patch not found: $patch_file" >&2
  exit 1
fi
for f in \
  "$susfs_repo/kernel_patches/fs/susfs.c" \
  "$susfs_repo/kernel_patches/include/linux/susfs.h" \
  "$susfs_repo/kernel_patches/include/linux/susfs_def.h"; do
  [[ -f "$f" ]] || { echo "SUSFS source file missing: $f" >&2; exit 1; }
done

cd "$COMMON_REPO"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "common repo must be clean before applying SUSFS update" >&2
  git status --short >&2
  exit 1
fi

susfs_commit="$(git log --grep='ANDROID: port SUSFS' --format=%H -1 || true)"
if [[ -z "$susfs_commit" ]]; then
  echo "Could not find previous 'ANDROID: port SUSFS' commit in common history" >&2
  exit 1
fi
parent="${susfs_commit}^"
mapfile -t touched_files < <(git show --name-only --format= "$susfs_commit" | sed '/^$/d')
if (( ${#touched_files[@]} == 0 )); then
  echo "Previous SUSFS commit has no touched files" >&2
  exit 1
fi

# Return the existing SUSFS port files to the pre-SUSFS state, then apply the
# newer upstream SUSFS patch from a clean base. This keeps unrelated Lokum commits
# (branding, DMV hooks, docs) intact.
for path in "${touched_files[@]}"; do
  if git cat-file -e "$parent:$path" 2>/dev/null; then
    git checkout "$parent" -- "$path"
  else
    git rm -f --ignore-unmatch -- "$path" >/dev/null
    rm -f -- "$path"
  fi
done

mkdir -p fs include/linux
cp -f "$susfs_repo/kernel_patches/fs/susfs.c" fs/susfs.c
cp -f "$susfs_repo/kernel_patches/include/linux/susfs.h" include/linux/susfs.h
cp -f "$susfs_repo/kernel_patches/include/linux/susfs_def.h" include/linux/susfs_def.h

git apply --3way "$patch_file"
"$SCRIPT_DIR/ensure-susfs-config.sh" arch/arm64/configs/xiaomi_sm8850_bootimg.fragment

git add -A
if git diff --cached --quiet; then
  echo "SUSFS update produced no source changes."
else
  susfs_head="$(git -C "$susfs_repo" rev-parse HEAD)"
  susfs_version="$(grep -Rho 'SUSFS_VERSION[[:space:]]*"v[^"]*"' include/linux/susfs*.h fs/susfs.c 2>/dev/null | head -n1 | sed -E 's/.*"(v[^"]+)".*/\1/' || true)"
  susfs_version="${susfs_version:-SUSFS}"
  git commit -m "ANDROID: update SUSFS port to ${susfs_version}" \
    -m "SUSFS source: ${susfs_head}"
fi
