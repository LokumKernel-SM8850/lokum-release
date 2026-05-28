#!/usr/bin/env bash
set -euo pipefail

RELEASE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$RELEASE_ROOT/.github/workflows/lokum-auto-release.yml"
fail=0

expect_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "missing required file: ${path#$RELEASE_ROOT/}" >&2
    fail=1
  fi
}

expect_text() {
  local path="$1" pattern="$2" label="$3"
  if ! grep -Eq "$pattern" "$path"; then
    echo "missing $label in ${path#$RELEASE_ROOT/}" >&2
    fail=1
  fi
}

expect_file "$RELEASE_ROOT/scripts/ci/list-release-lanes.sh"
expect_file "$RELEASE_ROOT/scripts/ci/cleanup-runner-state.sh"
expect_text "$workflow" 'id: discover_lanes|id: discover' 'dynamic lane discovery step'
expect_text "$workflow" 'fromJson\(' 'dynamic matrix from discovery output'
expect_text "$workflow" 'max-parallel:[[:space:]]*1' 'single-workspace matrix serialization'
expect_text "$workflow" 'cleanup-runner-state\.sh' 'always-on runner cleanup step'
expect_text "$workflow" 'if:[[:space:]]*\$\{\{ always\(\) \}\}' 'cleanup runs even after failures'
expect_text "$workflow" 'lanes:' 'workflow_dispatch lanes input'
expect_text "$workflow" 'cleanup_after_run:' 'workflow_dispatch cleanup toggle'

if grep -Eq 'default:[[:space:]]*manifests/' "$workflow"; then
  echo "auto-release workflow still defaults to one static manifest" >&2
  fail=1
fi
if grep -Eq 'inputs\.(force_build|update_ksun|update_susfs|publish_release|cleanup_after_run|cleanup_caches)[[:space:]]*\|\|' "$workflow"; then
  echo "boolean workflow inputs must not use || fallbacks because manual false would be overwritten" >&2
  fail=1
fi
if grep -Eq '/media/|/home/|LOCAL_BUILD_ROOT' "$workflow"; then
  echo "auto-release workflow must not expose a host-specific workspace path; use LOKUM_WORKSPACE" >&2
  fail=1
fi
expect_text "$workflow" 'LOKUM_WORKSPACE must point' 'self-hosted workspace validation'

matrix_json="$(LANES=all FORCE_BUILD=true LOKUM_LIST_RELEASE_LANES_OFFLINE=true "$RELEASE_ROOT/scripts/ci/list-release-lanes.sh" 2>/tmp/lokum-list-lanes-test.err || true)"
if [[ -z "$matrix_json" ]]; then
  cat /tmp/lokum-list-lanes-test.err >&2 || true
  echo "lane discovery did not produce JSON" >&2
  fail=1
elif ! python3 - "$matrix_json" <<'PY'
import json, sys
matrix = json.loads(sys.argv[1])
items = matrix.get("include", [])
assert len(items) >= 3, items
for item in items:
    assert item["manifest"].startswith("manifests/"), item
    assert item["source_branch"], item
    assert item["release_id"].startswith("lokumkernel-sm8850-"), item
PY
then
  echo "lane discovery JSON is invalid" >&2
  fail=1
fi

exit "$fail"
