#!/usr/bin/env bash
set -euo pipefail

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

setup_proxmox_ssh() {
  require_env PROXMOX_SSH_TARGET
  ssh_base=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
  scp_base=(scp -q -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
  if [[ -n "${PROXMOX_SSH_PRIVATE_KEY:-}" ]]; then
    require_env RUNNER_TEMP
    proxmox_key="$RUNNER_TEMP/lokum-proxmox-runner-install-key"
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
  tmp_path="/tmp/lokum-runner-${vmid}-$(basename "$ct_path")"
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
  if [[ -n "${tmp_dir:-}" && -d "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
  fi
  exit "$status"
}

require_command gh
require_command ssh
require_command scp

REPOSITORY_FULL_NAME="${REPOSITORY_FULL_NAME:-${GITHUB_REPOSITORY:-LokumKernel-SM8850/lokum-release}}"
PROXMOX_NODE="${PROXMOX_NODE:-}"
PROXMOX_RUNNER_STORAGE="${PROXMOX_RUNNER_STORAGE:-${PROXMOX_STORAGE:-}}"
PROXMOX_RUNNER_DISK_GB="${PROXMOX_RUNNER_DISK_GB:-8}"
PROXMOX_RUNNER_CORES="${PROXMOX_RUNNER_CORES:-1}"
PROXMOX_RUNNER_CPULIMIT="${PROXMOX_RUNNER_CPULIMIT:-0.2}"
PROXMOX_RUNNER_CPUUNITS="${PROXMOX_RUNNER_CPUUNITS:-64}"
PROXMOX_RUNNER_MEMORY_MB="${PROXMOX_RUNNER_MEMORY_MB:-128}"
PROXMOX_RUNNER_SWAP_MB="${PROXMOX_RUNNER_SWAP_MB:-256}"
PROXMOX_RUNNER_BRIDGE="${PROXMOX_RUNNER_BRIDGE:-${PROXMOX_CT_BRIDGE:-vmbr0}}"
PROXMOX_RUNNER_IP="${PROXMOX_RUNNER_IP:-dhcp}"
PROXMOX_RUNNER_OSTYPE="${PROXMOX_RUNNER_OSTYPE:-debian}"
PROXMOX_RUNNER_UNPRIVILEGED="${PROXMOX_RUNNER_UNPRIVILEGED:-1}"
PROXMOX_RUNNER_FEATURES="${PROXMOX_RUNNER_FEATURES:-nesting=1,keyctl=1}"
PROXMOX_RUNNER_VMID="${PROXMOX_RUNNER_VMID:-}"
RUNNER_NAME="${RUNNER_NAME:-lokum-proxmox}"
RUNNER_LABELS="${RUNNER_LABELS:-lokum-proxmox}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"
RUNNER_REPLACE="${RUNNER_REPLACE:-true}"
LOKUM_NAMESERVER="${LOKUM_NAMESERVER:-1.1.1.1}"
LOKUM_FALLBACK_NAMESERVER="${LOKUM_FALLBACK_NAMESERVER:-8.8.8.8}"
REPO_URL="https://github.com/${REPOSITORY_FULL_NAME}"

require_env PROXMOX_NODE
require_env PROXMOX_RUNNER_STORAGE
require_env PROXMOX_RUNNER_TEMPLATE

tmp_dir="$(mktemp -d)"
trap cleanup EXIT INT TERM
setup_proxmox_ssh

remote "command -v pct >/dev/null && command -v pvesh >/dev/null && pvesm status | grep -F $(shell_quote "$PROXMOX_RUNNER_STORAGE") >/dev/null"
remote "pvesm path $(shell_quote "$PROXMOX_RUNNER_TEMPLATE") >/dev/null"

if [[ -n "$PROXMOX_RUNNER_VMID" ]]; then
  vmid="$PROXMOX_RUNNER_VMID"
else
  vmid="$(remote "pvesh get /cluster/nextid" | tr -dc '0-9')"
fi
if [[ -z "$vmid" ]]; then
  echo "Could not allocate Proxmox VMID" >&2
  exit 1
fi

net0="name=eth0,bridge=${PROXMOX_RUNNER_BRIDGE},ip=${PROXMOX_RUNNER_IP}"
description="lokum GitHub Actions orchestrator runner for ${REPOSITORY_FULL_NAME}"

if remote "pct status $(shell_quote "$vmid") >/dev/null 2>&1"; then
  echo "Runner CT already exists: $vmid"
else
  echo "Creating runner CT $vmid with configured Proxmox node/storage (${PROXMOX_RUNNER_DISK_GB}G)"
  remote "pct create $(shell_quote "$vmid") $(shell_quote "$PROXMOX_RUNNER_TEMPLATE") \
    --hostname $(shell_quote "lokum-runner") \
    --storage $(shell_quote "$PROXMOX_RUNNER_STORAGE") \
    --rootfs $(shell_quote "${PROXMOX_RUNNER_STORAGE}:${PROXMOX_RUNNER_DISK_GB}") \
    --cores $(shell_quote "$PROXMOX_RUNNER_CORES") \
    --cpulimit $(shell_quote "$PROXMOX_RUNNER_CPULIMIT") \
    --cpuunits $(shell_quote "$PROXMOX_RUNNER_CPUUNITS") \
    --memory $(shell_quote "$PROXMOX_RUNNER_MEMORY_MB") \
    --swap $(shell_quote "$PROXMOX_RUNNER_SWAP_MB") \
    --nameserver $(shell_quote "$LOKUM_NAMESERVER") \
    --net0 $(shell_quote "$net0") \
    --ostype $(shell_quote "$PROXMOX_RUNNER_OSTYPE") \
    --unprivileged $(shell_quote "$PROXMOX_RUNNER_UNPRIVILEGED") \
    --features $(shell_quote "$PROXMOX_RUNNER_FEATURES") \
    --onboot 1 \
    --tags lokum-runner \
    --description $(shell_quote "$description")"
fi

remote "pct start $(shell_quote "$vmid") || true"
remote "pct exec $(shell_quote "$vmid") -- bash -lc 'for i in {1..60}; do getent hosts github.com >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1'"

registration_token="$(gh api -X POST "repos/${REPOSITORY_FULL_NAME}/actions/runners/registration-token" -q .token)"
if [[ -z "$registration_token" ]]; then
  echo "Could not acquire GitHub Actions runner registration token" >&2
  exit 1
fi

cat > "$tmp_dir/runner.env" <<EOF_ENV
REPO_URL=$(shell_quote "$REPO_URL")
RUNNER_TOKEN=$(shell_quote "$registration_token")
RUNNER_NAME=$(shell_quote "$RUNNER_NAME")
RUNNER_LABELS=$(shell_quote "$RUNNER_LABELS")
RUNNER_WORKDIR=$(shell_quote "$RUNNER_WORKDIR")
RUNNER_REPLACE=$(shell_quote "$RUNNER_REPLACE")
LOKUM_NAMESERVER=$(shell_quote "$LOKUM_NAMESERVER")
LOKUM_FALLBACK_NAMESERVER=$(shell_quote "$LOKUM_FALLBACK_NAMESERVER")
EOF_ENV

cat > "$tmp_dir/install-runner-inside-ct.sh" <<'EOF_INNER'
#!/usr/bin/env bash
set -euo pipefail
ENV_FILE="/root/lokum-runner.env"
# shellcheck source=/dev/null
source "$ENV_FILE"
export DEBIAN_FRONTEND=noninteractive
configure_network_defaults() {
  local primary="${LOKUM_NAMESERVER:-1.1.1.1}"
  local fallback="${LOKUM_FALLBACK_NAMESERVER:-8.8.8.8}"
  if [[ -f /etc/dhcp/dhclient.conf ]] && ! grep -q 'Lokum fixed DNS' /etc/dhcp/dhclient.conf; then
    cat >> /etc/dhcp/dhclient.conf <<EOF_DHCP

# Lokum fixed DNS: keep GitHub Actions checkout independent from LAN DNS hiccups.
supersede domain-name-servers ${primary}, ${fallback};
supersede domain-search "";
EOF_DHCP
  fi
  cat > /etc/resolv.conf <<EOF_RESOLV
nameserver ${primary}
nameserver ${fallback}
options timeout:2 attempts:3 rotate
EOF_RESOLV
  grep -q '^precedence ::ffff:0:0/96  100$' /etc/gai.conf 2>/dev/null \
    || printf '\nprecedence ::ffff:0:0/96  100\n' >> /etc/gai.conf
}
configure_network_defaults
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git jq openssh-client sudo tar gzip
if ! id actions >/dev/null 2>&1; then
  useradd -m -s /bin/bash actions
fi
install -d -o actions -g actions /opt/actions-runner
cd /opt/actions-runner
if [[ ! -x ./config.sh ]]; then
  curl_cmd=(curl -4 --retry 5 --retry-delay 2 --connect-timeout 20 -fsSL)
  tag="$("${curl_cmd[@]}" https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name)"
  version="${tag#v}"
  arch="x64"
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "Unsupported runner architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  "${curl_cmd[@]}" -O "https://github.com/actions/runner/releases/download/${tag}/actions-runner-linux-${arch}-${version}.tar.gz"
  tar xzf "actions-runner-linux-${arch}-${version}.tar.gz"
  rm -f "actions-runner-linux-${arch}-${version}.tar.gz"
  chown -R actions:actions /opt/actions-runner
fi
if [[ -f .runner ]]; then
  sudo -u actions ./config.sh remove --token "$RUNNER_TOKEN" || true
fi
replace_arg=()
if [[ "${RUNNER_REPLACE,,}" == "true" || "$RUNNER_REPLACE" == "1" ]]; then
  replace_arg=(--replace)
fi
sudo -u actions ./config.sh \
  --unattended \
  --url "$REPO_URL" \
  --token "$RUNNER_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --work "$RUNNER_WORKDIR" \
  "${replace_arg[@]}"
./svc.sh install actions
configure_network_defaults
./svc.sh start
systemctl is-active actions.runner.*.service
rm -f "$ENV_FILE"
EOF_INNER

remote_copy_to_ct "$tmp_dir/runner.env" "/root/lokum-runner.env" "600"
remote_copy_to_ct "$tmp_dir/install-runner-inside-ct.sh" "/root/install-lokum-runner.sh" "700"
remote "pct exec $(shell_quote "$vmid") -- bash -lc /root/install-lokum-runner.sh"
remote "pct exec $(shell_quote "$vmid") -- bash -lc 'hostname; systemctl --no-pager --full status actions.runner.*.service | sed -n \"1,35p\"'"

echo "Runner CT ready: $vmid ($RUNNER_NAME, labels: $RUNNER_LABELS)"
