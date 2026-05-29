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
expect_file "$RELEASE_ROOT/scripts/ci/proxmox-auto-release.sh"
expect_file "$RELEASE_ROOT/scripts/ci/proxmox-guest-build.sh"
expect_file "$RELEASE_ROOT/scripts/ci/install-proxmox-runner.sh"
expect_file "$RELEASE_ROOT/manifests/repo-sm8850-ci.xml"
expect_text "$workflow" 'id: discover_lanes|id: discover' 'dynamic lane discovery step'
expect_text "$workflow" 'fromJson\(' 'dynamic matrix from discovery output'
expect_text "$workflow" 'max-parallel:[[:space:]]*1' 'single-workspace matrix serialization'
expect_text "$workflow" 'cleanup-runner-state\.sh' 'always-on runner cleanup step'
expect_text "$workflow" 'if:[[:space:]]*\$\{\{ always\(\)' 'cleanup runs even after failures'
expect_text "$workflow" 'lanes:' 'workflow_dispatch lanes input'
expect_text "$workflow" 'cleanup_after_run:' 'workflow_dispatch cleanup toggle'
expect_text "$workflow" 'executor:' 'executor selector input'
expect_text "$workflow" 'default:[[:space:]]*proxmox-ct' 'Proxmox CT default executor'
expect_text "$workflow" 'cron:[[:space:]]*"0 9 \* \* \*"' 'daily schedule at 12:00 Turkey time'
expect_text "$workflow" 'proxmox-auto-release\.sh' 'Proxmox CT executor step'
expect_text "$workflow" 'secrets\.PROXMOX_NODE' 'secret-backed Proxmox node setting'
expect_text "$workflow" 'secrets\.PROXMOX_STORAGE' 'secret-backed Proxmox storage setting'
expect_text "$workflow" 'secrets\.PROXMOX_SSH_TARGET' 'secret-backed Proxmox SSH target setting'
expect_text "$workflow" 'secrets\.LOKUM_WORKSPACE' 'secret-backed local workspace setting'
expect_text "$workflow" 'LOKUM_GIT_TOKEN' 'cross-repository Git write token support'
expect_text "$workflow" 'lokum-proxmox' 'dedicated Proxmox runner label'
expect_text "$RELEASE_ROOT/scripts/ci/install-proxmox-runner.sh" 'RUNNER_LABELS.*lokum-proxmox' 'Proxmox runner installer label'


if grep -Eq 'vars\.(LOKUM_WORKSPACE|PROXMOX_SSH_TARGET|PROXMOX_NODE|PROXMOX_STORAGE|PROXMOX_CT_TEMPLATE|PROXMOX_CT_BRIDGE)' "$workflow"; then
  echo "public CI workflow must read local infrastructure identifiers from secrets, not variables" >&2
  fail=1
fi

if grep -Eq 'PROXMOX_NODE:.*\|\|[[:space:]]*["'"'"']|PROXMOX_STORAGE:.*\|\|[[:space:]]*["'"'"']|PROXMOX_(NODE|STORAGE)="\$\{PROXMOX_(NODE|STORAGE):-[^}]+' "$workflow" "$RELEASE_ROOT/scripts/ci/proxmox-auto-release.sh" "$RELEASE_ROOT/scripts/ci/install-proxmox-runner.sh"; then
  echo "public CI files must not contain hardcoded Proxmox node or storage defaults" >&2
  fail=1
fi
if grep -Eq '/media/|/home/|root@[0-9]|https?://[^[:space:]]*:[0-9]{2,5}' "$workflow" "$RELEASE_ROOT/scripts/ci/proxmox-auto-release.sh" "$RELEASE_ROOT/scripts/ci/install-proxmox-runner.sh"; then
  echo "public CI files must not contain host-specific paths, SSH targets, or private service URLs" >&2
  fail=1
fi

if grep -Eq 'default:[[:space:]]*manifests/' "$workflow"; then
  echo "auto-release workflow still defaults to one static manifest" >&2
  fail=1
fi
if grep -Eq 'inputs\.(force_build|update_ksun|update_susfs|publish_release|cleanup_after_run|cleanup_caches)[[:space:]]*\|\|' "$workflow"; then
  echo "boolean workflow inputs must not use || fallbacks because manual false would be overwritten" >&2
  fail=1
fi
if grep -Eq '/media/|/home/' "$workflow"; then
  echo "auto-release workflow must not expose a host-specific workspace path; use LOKUM_WORKSPACE" >&2
  fail=1
fi
expect_text "$workflow" 'LOKUM_WORKSPACE must point' 'self-hosted workspace validation'

if grep -Eq 'file://|pandora-local' "$RELEASE_ROOT/manifests/repo-sm8850-ci.xml"; then
  echo "CI repo manifest must be usable by ephemeral CTs and must not reference local file remotes" >&2
  fail=1
fi
if ! python3 - "$RELEASE_ROOT/manifests/repo-sm8850-ci.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
projects = {p.get("path"): p for p in root.findall("project")}
assert projects["kernel_platform/common"].get("remote") == "lokum-github"
assert projects["kernel_platform/common"].get("name") == "android_kernel_xiaomi_sm8850.git"
assert projects["kernel_platform/soc-repo"].get("remote") == "clo-la"
assert projects["kernel_platform/prebuilts/rust"].get("remote") == "clo-la"
PY
then
  echo "CI repo manifest does not point critical projects at network remotes" >&2
  fail=1
fi

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
