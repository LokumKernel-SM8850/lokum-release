#!/usr/bin/env bash
set -euo pipefail
umask 077

ENV_FILE="/root/lokum-ci.env"
TOKEN_FILE="/root/lokum-gh-token"
GIT_TOKEN_FILE="/root/lokum-git-token"
OUTPUT_FILE="/root/lokum-gh-output"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Required environment value missing: $name" >&2
    exit 1
  fi
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command missing after setup: $cmd" >&2
    exit 1
  fi
}

configure_network_defaults() {
  if [[ -n "${LOKUM_NAMESERVER:-1.1.1.1}" ]]; then
    printf 'nameserver %s\n' "${LOKUM_NAMESERVER:-1.1.1.1}" > /etc/resolv.conf
  fi
  grep -q '^precedence ::ffff:0:0/96  100$' /etc/gai.conf 2>/dev/null \
    || printf '\nprecedence ::ffff:0:0/96  100\n' >> /etc/gai.conf
}

apt_install_base() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    bash ca-certificates coreutils curl file git jq openssh-client python3 \
    ripgrep rsync tar unzip xz-utils zip
}

install_repo_tool() {
  if command -v repo >/dev/null 2>&1; then
    return 0
  fi
  if apt-get install -y --no-install-recommends repo; then
    return 0
  fi
  curl -4 --retry 5 --retry-delay 2 --connect-timeout 20 -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo
  chmod 755 /usr/local/bin/repo
}

install_github_cli() {
  if command -v gh >/dev/null 2>&1; then
    return 0
  fi
  if apt-get install -y --no-install-recommends gh; then
    return 0
  fi
  install -d -m 0755 /etc/apt/keyrings
  curl -4 --retry 5 --retry-delay 2 --connect-timeout 20 -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  arch="$(dpkg --print-architecture)"
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' "$arch" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update
  apt-get install -y --no-install-recommends gh
}

setup_git_transport() {
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  if [[ -s "$GIT_TOKEN_FILE" ]]; then
    git_token="$(cat "$GIT_TOKEN_FILE")"
    git config --global url."https://x-access-token:${git_token}@github.com/".insteadOf "git@github.com:"
    git config --global url."https://x-access-token:${git_token}@github.com/".insteadOf "ssh://git@github.com/"
  fi
  if [[ -s /root/.ssh/id_ed25519 || -s /root/.ssh/id_rsa ]]; then
    ssh-keyscan github.com gitlab.com 2>/dev/null >> /root/.ssh/known_hosts || true
    chmod 600 /root/.ssh/known_hosts /root/.ssh/id_* 2>/dev/null || true
  fi
  if [[ ! -s "$GIT_TOKEN_FILE" && ! -s /root/.ssh/id_ed25519 && ! -s /root/.ssh/id_rsa ]]; then
    echo "Missing GitHub write credential: provide LOKUM_GIT_TOKEN or LOKUM_CI_SSH_PRIVATE_KEY" >&2
    exit 1
  fi
  git config --global user.name "LokumKernel CI"
  git config --global user.email "ci@lokumkernel.local"
  git config --global init.defaultBranch main
}

setup_gh_auth() {
  if [[ ! -f "$TOKEN_FILE" ]]; then
    echo "Missing $TOKEN_FILE" >&2
    exit 1
  fi
  export GH_TOKEN
  GH_TOKEN="$(cat "$TOKEN_FILE")"
  gh auth status >/dev/null
}

sync_workspace() {
  require_env RELEASE_REPO_URL
  require_env RELEASE_TOOLING_REF
  require_env LOKUM_WORKSPACE
  require_env LOKUM_REPO_MANIFEST
  require_env MANIFEST_RELATIVE

  mkdir -p "$LOKUM_WORKSPACE"
  cd "$LOKUM_WORKSPACE"

  repo_init_args=(-u "$RELEASE_REPO_URL" -b "${RELEASE_TOOLING_BRANCH:-main}" -m "$LOKUM_REPO_MANIFEST")
  if [[ -n "${REPO_INIT_DEPTH:-}" ]]; then
    repo_init_args+=(--depth="$REPO_INIT_DEPTH")
  fi
  repo init "${repo_init_args[@]}"
  repo sync -c --no-tags --no-clone-bundle --force-sync -j"${SYNC_JOBS:-8}"

  release_dir="$LOKUM_WORKSPACE/LokumKernel-SM8850/lokum-release"
  rm -rf "$release_dir"
  mkdir -p "$(dirname "$release_dir")"
  git clone "$RELEASE_REPO_URL" "$release_dir"
  git -C "$release_dir" fetch origin "$RELEASE_TOOLING_REF" --depth=1 || git -C "$release_dir" fetch origin main --depth=1
  git -C "$release_dir" checkout --detach "$RELEASE_TOOLING_REF" || git -C "$release_dir" checkout --detach origin/main
}

run_release_lane() {
  release_dir="$LOKUM_WORKSPACE/LokumKernel-SM8850/lokum-release"
  manifest_path="$release_dir/$MANIFEST_RELATIVE"
  if [[ ! -f "$manifest_path" ]]; then
    echo "Manifest not found in release tooling checkout: $manifest_path" >&2
    exit 1
  fi

  export GH_TOKEN
  GH_TOKEN="$(cat "$TOKEN_FILE")"
  export WORKSPACE_ROOT="$LOKUM_WORKSPACE"
  export MANIFEST="$manifest_path"
  export GITHUB_OUTPUT="$OUTPUT_FILE"
  export CACHE_DIR="$release_dir/.cache"
  export BAZEL_OUTPUT_USER_ROOT="$LOKUM_WORKSPACE/.bazel-output-user-root"

  : > "$OUTPUT_FILE"
  "$release_dir/scripts/ci/auto-release.sh"
}

configure_network_defaults
apt_install_base
install_repo_tool
install_github_cli
require_command repo
require_command gh
require_command git
require_command rg
setup_git_transport
setup_gh_auth
sync_workspace
run_release_lane

du -sh "$LOKUM_WORKSPACE" "$LOKUM_WORKSPACE/kernel_platform" 2>/dev/null || true
