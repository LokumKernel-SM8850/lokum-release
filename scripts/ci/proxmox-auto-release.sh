#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="${MANIFEST:-$RELEASE_ROOT/manifests/sm8850-android16-6.12.38-droidspaces-exp.env}"

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command missing: $cmd" >&2
    exit 1
  fi
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Required environment value missing: $name" >&2
    exit 1
  fi
}

shell_quote() {
  printf '%q' "$1"
}

bool_true() {
  [[ "${1,,}" == "true" || "$1" == "1" || "${1,,}" == "yes" ]]
}

manifest_relative() {
  local abs manifest_dir rel
  abs="$(cd "$(dirname "$MANIFEST")" && pwd)/$(basename "$MANIFEST")"
  manifest_dir="$RELEASE_ROOT/"
  rel="${abs#"$manifest_dir"}"
  if [[ "$rel" == "$abs" || ! -f "$abs" ]]; then
    echo "MANIFEST must point inside the release repo checkout: $MANIFEST" >&2
    exit 1
  fi
  printf '%s\n' "$rel"
}

setup_proxmox_ssh() {
  require_env PROXMOX_SSH_TARGET
  ssh_base=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
  scp_base=(scp -q -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
  if [[ -n "${PROXMOX_SSH_PRIVATE_KEY:-}" ]]; then
    require_env RUNNER_TEMP
    proxmox_key="$RUNNER_TEMP/lokum-proxmox-ssh-key"
    umask 077
    printf '%s\n' "$PROXMOX_SSH_PRIVATE_KEY" > "$proxmox_key"
    chmod 600 "$proxmox_key"
    ssh_base+=(-i "$proxmox_key")
    scp_base+=(-i "$proxmox_key")
  fi
}

remote() {
  "${ssh_base[@]}" "$PROXMOX_SSH_TARGET" "$@"
}

remote_copy_to_ct() {
  local local_file="$1" ct_path="$2" mode="$3" tmp_path
  tmp_path="/tmp/lokum-ci-${vmid}-$(basename "$ct_path")"
  "${scp_base[@]}" "$local_file" "$PROXMOX_SSH_TARGET:$tmp_path"
  remote "set -euo pipefail
if pct help 2>&1 | grep -Eq '^  push|^pct push| push '; then
  pct push $(shell_quote "$vmid") $(shell_quote "$tmp_path") $(shell_quote "$ct_path") --perms $(shell_quote "$mode")
else
  pct exec $(shell_quote "$vmid") -- bash -lc 'cat > $(shell_quote "$ct_path") && chmod $(shell_quote "$mode") $(shell_quote "$ct_path")' < $(shell_quote "$tmp_path")
fi
rm -f $(shell_quote "$tmp_path")"
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ "${ct_created:-false}" == "true" && -n "${vmid:-}" ]]; then
    echo "Cleaning Proxmox CT $vmid"
    remote "pct status $(shell_quote "$vmid") >/dev/null 2>&1 && pct stop $(shell_quote "$vmid") --skiplock 1 || true" || true
    remote "pct status $(shell_quote "$vmid") >/dev/null 2>&1 && pct destroy $(shell_quote "$vmid") --purge 1 --destroy-unreferenced-disks 1 || true" || true
  fi
  if [[ -n "${tmp_dir:-}" && -d "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
  fi
  exit "$status"
}

require_command ssh
require_command scp
require_command base64
require_command python3
require_env GH_TOKEN
if [[ -z "${LOKUM_CI_SSH_PRIVATE_KEY:-}" && -z "${LOKUM_GIT_TOKEN:-}" ]]; then
  echo "Required GitHub write credential missing: set LOKUM_CI_SSH_PRIVATE_KEY or LOKUM_GIT_TOKEN" >&2
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

PROXMOX_NODE="${PROXMOX_NODE:-PROXMOX_NODE}"
PROXMOX_STORAGE="${PROXMOX_STORAGE:-PROXMOX_STORAGE}"
PROXMOX_CT_DISK_GB="${PROXMOX_CT_DISK_GB:-120}"
PROXMOX_CT_CORES="${PROXMOX_CT_CORES:-12}"
PROXMOX_CT_MEMORY_MB="${PROXMOX_CT_MEMORY_MB:-24576}"
PROXMOX_CT_SWAP_MB="${PROXMOX_CT_SWAP_MB:-4096}"
PROXMOX_CT_BRIDGE="${PROXMOX_CT_BRIDGE:-vmbr0}"
PROXMOX_CT_IP="${PROXMOX_CT_IP:-dhcp}"
PROXMOX_CT_OSTYPE="${PROXMOX_CT_OSTYPE:-debian}"
PROXMOX_CT_UNPRIVILEGED="${PROXMOX_CT_UNPRIVILEGED:-1}"
PROXMOX_CT_FEATURES="${PROXMOX_CT_FEATURES:-nesting=1,keyctl=1}"
PROXMOX_CT_TEMPLATE="${PROXMOX_CT_TEMPLATE:-}"
PROXMOX_CT_VMID="${PROXMOX_CT_VMID:-}"
SYNC_JOBS="${SYNC_JOBS:-12}"
LOKUM_REPO_MANIFEST="${LOKUM_REPO_MANIFEST:-manifests/repo-sm8850-ci.xml}"
LOKUM_CT_WORKSPACE="${LOKUM_CT_WORKSPACE:-/build/lokum-sm8850}"
LOKUM_NAMESERVER="${LOKUM_NAMESERVER:-1.1.1.1}"
RELEASE_REPO_URL="${RELEASE_REPO_URL:-https://github.com/${GITHUB_REPOSITORY:-LokumKernel-SM8850/lokum-release}.git}"
RELEASE_TOOLING_REF="${RELEASE_TOOLING_REF:-${GITHUB_SHA:-main}}"
RELEASE_TOOLING_BRANCH="${RELEASE_TOOLING_BRANCH:-main}"
RELEASE_SUFFIX="${RELEASE_SUFFIX:-}"

require_env PROXMOX_CT_TEMPLATE
setup_proxmox_ssh
trap cleanup EXIT INT TERM

tmp_dir="$(mktemp -d)"
ct_created=false
manifest_rel="$(manifest_relative)"
run_id="${GITHUB_RUN_ID:-manual}"
attempt="${GITHUB_RUN_ATTEMPT:-1}"
hostname="lokum-ci-${run_id}-${attempt}"
# Proxmox hostnames are conservative DNS labels.
hostname="${hostname//[^A-Za-z0-9-]/-}"
hostname="${hostname:0:60}"

remote "command -v pct >/dev/null && command -v pvesh >/dev/null && pvesm status | grep -F $(shell_quote "$PROXMOX_STORAGE") >/dev/null"
remote "pvesm path $(shell_quote "$PROXMOX_CT_TEMPLATE") >/dev/null"

if [[ -n "$PROXMOX_CT_VMID" ]]; then
  vmid="$PROXMOX_CT_VMID"
else
  vmid="$(remote "pvesh get /cluster/nextid" | tr -dc '0-9')"
fi
if [[ -z "$vmid" ]]; then
  echo "Could not allocate Proxmox VMID" >&2
  exit 1
fi

description="lokum-ci run=${run_id} attempt=${attempt} node=${PROXMOX_NODE} created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
net0="name=eth0,bridge=${PROXMOX_CT_BRIDGE},ip=${PROXMOX_CT_IP}"

echo "Creating Proxmox CT $vmid on $PROXMOX_NODE using $PROXMOX_STORAGE (${PROXMOX_CT_DISK_GB}G)"
remote "pct create $(shell_quote "$vmid") $(shell_quote "$PROXMOX_CT_TEMPLATE") \
  --hostname $(shell_quote "$hostname") \
  --storage $(shell_quote "$PROXMOX_STORAGE") \
  --rootfs $(shell_quote "${PROXMOX_STORAGE}:${PROXMOX_CT_DISK_GB}") \
  --cores $(shell_quote "$PROXMOX_CT_CORES") \
  --memory $(shell_quote "$PROXMOX_CT_MEMORY_MB") \
  --swap $(shell_quote "$PROXMOX_CT_SWAP_MB") \
  --net0 $(shell_quote "$net0") \
  --ostype $(shell_quote "$PROXMOX_CT_OSTYPE") \
  --unprivileged $(shell_quote "$PROXMOX_CT_UNPRIVILEGED") \
  --features $(shell_quote "$PROXMOX_CT_FEATURES") \
  --onboot 0 \
  --tags lokum-ci \
  --description $(shell_quote "$description")"
ct_created=true

remote "pct start $(shell_quote "$vmid")"
remote "pct exec $(shell_quote "$vmid") -- bash -lc 'for i in {1..60}; do getent hosts github.com >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1'"

cat > "$tmp_dir/lokum-ci.env" <<EOF_ENV
RELEASE_REPO_URL=$(shell_quote "$RELEASE_REPO_URL")
RELEASE_TOOLING_REF=$(shell_quote "$RELEASE_TOOLING_REF")
RELEASE_TOOLING_BRANCH=$(shell_quote "$RELEASE_TOOLING_BRANCH")
LOKUM_WORKSPACE=$(shell_quote "$LOKUM_CT_WORKSPACE")
LOKUM_REPO_MANIFEST=$(shell_quote "$LOKUM_REPO_MANIFEST")
MANIFEST_RELATIVE=$(shell_quote "$manifest_rel")
SYNC_JOBS=$(shell_quote "$SYNC_JOBS")
SOURCE_BRANCH=$(shell_quote "${SOURCE_BRANCH:-}")
FORCE_BUILD=$(shell_quote "${FORCE_BUILD:-true}")
UPDATE_KSUNEXT=$(shell_quote "${UPDATE_KSUNEXT:-true}")
UPDATE_SUSFS=$(shell_quote "${UPDATE_SUSFS:-true}")
PUBLISH_RELEASE=$(shell_quote "${PUBLISH_RELEASE:-true}")
RELEASE_SUFFIX=$(shell_quote "$RELEASE_SUFFIX")
PUSH_SOURCE_BRANCH=$(shell_quote "${PUSH_SOURCE_BRANCH:-true}")
PUSH_KSUNEXT_BRANCH=$(shell_quote "${PUSH_KSUNEXT_BRANCH:-true}")
LOKUM_NAMESERVER=$(shell_quote "$LOKUM_NAMESERVER")
EOF_ENV

printf '%s\n' "$GH_TOKEN" > "$tmp_dir/gh-token"
chmod 600 "$tmp_dir/gh-token"
if [[ -n "${LOKUM_CI_SSH_PRIVATE_KEY:-}" ]]; then
  printf '%s\n' "$LOKUM_CI_SSH_PRIVATE_KEY" > "$tmp_dir/github-key"
  chmod 600 "$tmp_dir/github-key"
fi
if [[ -n "${LOKUM_GIT_TOKEN:-}" ]]; then
  printf '%s\n' "$LOKUM_GIT_TOKEN" > "$tmp_dir/git-token"
  chmod 600 "$tmp_dir/git-token"
fi

remote "pct exec $(shell_quote "$vmid") -- bash -lc 'mkdir -p /root/.ssh /build && chmod 700 /root/.ssh'"
remote_copy_to_ct "$SCRIPT_DIR/proxmox-guest-build.sh" "/root/lokum-guest-build.sh" "700"
remote_copy_to_ct "$tmp_dir/lokum-ci.env" "/root/lokum-ci.env" "600"
remote_copy_to_ct "$tmp_dir/gh-token" "/root/lokum-gh-token" "600"
if [[ -f "$tmp_dir/github-key" ]]; then
  remote_copy_to_ct "$tmp_dir/github-key" "/root/.ssh/id_ed25519" "600"
fi
if [[ -f "$tmp_dir/git-token" ]]; then
  remote_copy_to_ct "$tmp_dir/git-token" "/root/lokum-git-token" "600"
fi

remote "pct exec $(shell_quote "$vmid") -- bash -lc /root/lokum-guest-build.sh"

result_file="$tmp_dir/github-output"
if remote "pct exec $(shell_quote "$vmid") -- test -s /root/lokum-gh-output"; then
  remote "pct exec $(shell_quote "$vmid") -- cat /root/lokum-gh-output" > "$result_file"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    cat "$result_file" >> "$GITHUB_OUTPUT"
  fi
  cat "$result_file"
fi

echo "Proxmox CT lane completed: $vmid"
