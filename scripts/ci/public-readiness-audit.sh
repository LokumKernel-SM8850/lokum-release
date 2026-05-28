#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE_ROOT="$(cd "$RELEASE_ROOT/../.." && pwd)"

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command missing: $cmd" >&2
    exit 1
  fi
}

require_command git
require_command awk
require_command sort

if (($#)); then
  repos=("$@")
else
  repos=("$RELEASE_ROOT")
  [[ -d "$RELEASE_ROOT/../android_kernel_xiaomi_sm8850/.git" ]] && repos+=("$RELEASE_ROOT/../android_kernel_xiaomi_sm8850")
  [[ -d "$WORKSPACE_ROOT/kernel_platform/KernelSU-Next/.git" ]] && repos+=("$WORKSPACE_ROOT/kernel_platform/KernelSU-Next")
fi

fail=0

is_allowed_sensitive_path() {
  local path="$1"
  case "$path" in
    manifests/*.env) return 0 ;;
    tools/testing/selftests/sgx/sign_key.pem) return 0 ;;
    scripts/ci/public-readiness-audit.sh) return 0 ;;
  esac
  return 1
}

scan_repo() {
  local repo="$1"
  local name
  name="$(basename "$repo")"
  echo "== Public readiness audit: $name =="

  if [[ ! -d "$repo/.git" ]]; then
    echo "Not a git repository: $repo" >&2
    fail=1
    return
  fi

  local dirty
  dirty="$(git -C "$repo" status --short)"
  if [[ -n "$dirty" && "$repo" != "$RELEASE_ROOT" ]]; then
    echo "WARN: $name has local uncommitted changes; audit continues against tracked files." >&2
  fi

  echo "-- tracked artifact and sensitive filenames --"
  local suspicious=()
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if is_allowed_sensitive_path "$path"; then
      continue
    fi
    suspicious+=("$path")
  done < <(
    git -C "$repo" ls-files \
      | grep -Ei '(^|/)(id_rsa|id_ed25519|.*\.(pem|key|jks|keystore|p12|mobileprovision|env)|.*(auth[_-]?token|access[_-]?token|secret|credential|credentials).*\.(json|txt|env|ya?ml|properties)|.*\.(img|apk|zip|tar\.gz))$' \
      || true
  )
  if ((${#suspicious[@]})); then
    for path in "${suspicious[@]}"; do
      printf 'Suspicious tracked path in %s: %s\n' "$name" "$path" >&2
    done
    fail=1
  else
    echo "ok"
  fi

  echo "-- tracked file size limits --"
  local oversized=()
  while IFS=$'\t' read -r size path; do
    [[ -z "${size:-}" ]] && continue
    if (( size >= 95000000 )); then
      oversized+=("$size $path")
    fi
  done < <(
    (cd "$repo" && git ls-files -z | xargs -0 -r du -b 2>/dev/null | sort -nr | awk '{print $1 "\t" $2}')
  )
  if ((${#oversized[@]})); then
    for item in "${oversized[@]}"; do
      printf 'Tracked file at/above 95MB in %s: %s\n' "$name" "$item" >&2
    done
    fail=1
  else
    echo "ok"
  fi

  echo "-- secret-looking content --"
  local secret_matches
  secret_matches="$({
    git -C "$repo" grep -I -n -E \
      '-----BEGIN (RSA |DSA |EC |OPENSSH |)PRIVATE KEY-----|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,}' \
      -- \
      ':!scripts/ci/public-readiness-audit.sh' \
      ':!tools/testing/selftests/sgx/sign_key.pem' \
      2>/dev/null || true
  })"
  if [[ -n "$secret_matches" ]]; then
    echo "$secret_matches" >&2
    fail=1
  else
    echo "ok"
  fi

  echo "-- workflow public safety --"
  local workflow_fail=0
  if [[ -d "$repo/.github/workflows" ]]; then
    local wf
    while IFS= read -r wf; do
      if grep -Eq 'pull_request_target:' "$wf"; then
        echo "Unsafe pull_request_target trigger in $wf" >&2
        workflow_fail=1
      fi
      if grep -Eq 'self-hosted' "$wf" && grep -Eq 'pull_request:|pull_request_target:' "$wf"; then
        echo "Self-hosted workflow must not run on pull_request in public repos: $wf" >&2
        workflow_fail=1
      fi
    done < <(find "$repo/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
  fi
  if (( workflow_fail )); then
    fail=1
  else
    echo "ok"
  fi
}

for repo in "${repos[@]}"; do
  scan_repo "$(cd "$repo" && pwd)"
done

exit "$fail"
