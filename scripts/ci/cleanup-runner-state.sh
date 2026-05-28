#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../common.sh
source "$RELEASE_ROOT/scripts/common.sh"

CLEAN_RELEASE_OUT="${CLEAN_RELEASE_OUT:-true}"
CLEAN_TEMP_MANIFESTS="${CLEAN_TEMP_MANIFESTS:-true}"
CLEAN_TOOL_CACHE="${CLEAN_TOOL_CACHE:-false}"
CLEAN_BAZEL_OUTPUT="${CLEAN_BAZEL_OUTPUT:-false}"
RESET_REPOS="${RESET_REPOS:-true}"
PRUNE_CI_BRANCHES="${PRUNE_CI_BRANCHES:-true}"
CLEAN_UNTRACKED_REPO_FILES="${CLEAN_UNTRACKED_REPO_FILES:-false}"

bool_true() { [[ "${1,,}" == "true" || "$1" == "1" || "${1,,}" == "yes" || "${1,,}" == "on" ]]; }

safe_rm_under() {
  local base="$1" target="$2" label="$3"
  [[ -n "$target" ]] || return 0
  local real_base real_target
  real_base="$(realpath -m "$base")"
  real_target="$(realpath -m "$target")"
  if [[ "$real_target" == "$real_base" || "$real_target" == "$real_base"/* ]]; then
    rm -rf -- "$real_target"
    printf 'removed %s: %s\n' "$label" "$real_target"
  else
    printf 'refusing to remove %s outside %s: %s\n' "$label" "$real_base" "$real_target" >&2
    return 1
  fi
}

reset_repo() {
  local repo="$1" name="$2"
  [[ -d "$repo/.git" ]] || return 0
  git -C "$repo" cherry-pick --abort >/dev/null 2>&1 || true
  git -C "$repo" rebase --abort >/dev/null 2>&1 || true
  git -C "$repo" merge --abort >/dev/null 2>&1 || true
  git -C "$repo" reset --hard >/dev/null
  if bool_true "$CLEAN_UNTRACKED_REPO_FILES"; then
    git -C "$repo" clean -fd >/dev/null
  fi
  if bool_true "$PRUNE_CI_BRANCHES"; then
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      git -C "$repo" branch -D "$branch" >/dev/null 2>&1 || true
    done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads/ci/)
  fi
  printf 'reset repo: %s\n' "$name"
}

if bool_true "$RESET_REPOS"; then
  reset_repo "$COMMON_REPO" common
  reset_repo "$KERNELSU_NEXT_REPO" KernelSU-Next
  reset_repo "$KERNEL_PLATFORM/susfs4ksu" susfs4ksu
fi

if bool_true "$CLEAN_RELEASE_OUT"; then
  safe_rm_under "$RELEASE_ROOT/out" "${AUTO_RELEASE_OUT_ROOT:-}" release-output
  if [[ -n "${AUTO_RELEASE_PACKAGE_OUT:-}" && -d "${AUTO_RELEASE_PACKAGE_OUT:-}" ]]; then
    safe_rm_under "$RELEASE_ROOT/out" "$AUTO_RELEASE_PACKAGE_OUT" package-output
  fi
fi

if bool_true "$CLEAN_TEMP_MANIFESTS"; then
  find "$RELEASE_ROOT/out" -maxdepth 1 -type f -name 'lokum-ci-manifest-*.env' -delete 2>/dev/null || true
  if [[ -n "${CI_MANIFEST_PATH:-}" ]]; then
    case "$(realpath -m "$CI_MANIFEST_PATH")" in
      "$(realpath -m "${RUNNER_TEMP:-/tmp}")"/*|"$(realpath -m "$RELEASE_ROOT/out")"/*) rm -f -- "$CI_MANIFEST_PATH" ;;
      *) printf 'refusing to remove temp manifest outside runner temp/out: %s\n' "$CI_MANIFEST_PATH" >&2 ;;
    esac
  fi
fi

if bool_true "$CLEAN_TOOL_CACHE"; then
  safe_rm_under "$RELEASE_ROOT" "$CACHE_DIR" tool-cache
fi

if bool_true "$CLEAN_BAZEL_OUTPUT"; then
  safe_rm_under "$WORKSPACE_ROOT" "$BAZEL_OUTPUT_USER_ROOT" bazel-output-user-root
fi

printf 'runner cleanup complete\n'
