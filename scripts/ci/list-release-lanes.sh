#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LANES="${LANES:-changed}"
FORCE_BUILD="${FORCE_BUILD:-false}"
UPDATE_KSUNEXT="${UPDATE_KSUNEXT:-true}"
UPDATE_SUSFS="${UPDATE_SUSFS:-true}"
OFFLINE="${LOKUM_LIST_RELEASE_LANES_OFFLINE:-false}"

python3 - "$RELEASE_ROOT" "$LANES" "$FORCE_BUILD" "$UPDATE_KSUNEXT" "$UPDATE_SUSFS" "$OFFLINE" <<'PY'
from __future__ import annotations
import json
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
lanes_raw = sys.argv[2].strip() or "changed"
force_build = sys.argv[3].lower() in {"1", "true", "yes", "on"}
update_ksu = sys.argv[4].lower() in {"1", "true", "yes", "on"}
update_susfs = sys.argv[5].lower() in {"1", "true", "yes", "on"}
offline = sys.argv[6].lower() in {"1", "true", "yes", "on"}

assignment = re.compile(r'^([A-Z0-9_]+)=(.*)$')

def parse_manifest(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        match = assignment.match(line)
        if not match:
            continue
        key, value = match.groups()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] == '"':
            value = value[1:-1]
        data[key] = value
    return data

def bool_text(value: bool) -> str:
    return "true" if value else "false"

def ls_remote(repo: str, ref: str) -> str:
    if offline:
        return "offline"
    out = subprocess.check_output(["git", "ls-remote", repo, ref], text=True)
    sha = out.split()[0] if out.split() else ""
    if not sha:
        raise SystemExit(f"Could not resolve {ref} from {repo}")
    return sha

selectors = [item.strip() for item in lanes_raw.split(",") if item.strip()]
selector_set = set(selectors)
mode = lanes_raw.lower()
if mode in {"all", "changed"}:
    selector_set = set()

include: list[dict[str, str]] = []
for manifest in sorted((root / "manifests").glob("*.env")):
    rel_manifest = manifest.relative_to(root).as_posix()
    data = parse_manifest(manifest)
    release_id = data.get("RELEASE_ID", "")
    source_branch = data.get("KERNEL_COMMON_BRANCH", "")
    if not release_id or not source_branch:
        raise SystemExit(f"Manifest missing RELEASE_ID or KERNEL_COMMON_BRANCH: {rel_manifest}")

    manifest_id = manifest.stem
    selected = mode in {"all", "changed"} or bool({rel_manifest, manifest_id, release_id, source_branch} & selector_set)
    if not selected:
        continue

    ksu_latest = data.get("KERNELSU_NEXT_BASE_CANDIDATE") or data.get("KERNELSU_NEXT_HEAD", "")
    susfs_latest = data.get("SUSFS_SOURCE_HEAD", "")
    ksu_changed = False
    susfs_changed = False
    if not offline:
        if update_ksu:
            ksu_latest = ls_remote(data.get("KERNELSU_NEXT_UPSTREAM_REPO", "https://github.com/KernelSU-Next/KernelSU-Next.git"), data.get("KERNELSU_NEXT_TRACK_REF", "refs/heads/dev"))
            ksu_pinned = data.get("KERNELSU_NEXT_BASE_CANDIDATE") or data.get("KERNELSU_NEXT_HEAD", "")
            ksu_changed = bool(ksu_pinned and ksu_latest != ksu_pinned)
        if update_susfs:
            susfs_latest = ls_remote(data.get("SUSFS_UPSTREAM_REPO", "https://gitlab.com/simonpunk/susfs4ksu.git"), data.get("SUSFS_TRACK_REF", "refs/heads/gki-android16-6.12"))
            susfs_pinned = data.get("SUSFS_SOURCE_HEAD", "")
            susfs_changed = bool(susfs_pinned and susfs_latest != susfs_pinned)

    should_build = force_build or mode == "all" or (mode != "changed") or ksu_changed or susfs_changed
    if not should_build:
        continue

    include.append({
        "manifest": rel_manifest,
        "source_branch": source_branch,
        "release_id": release_id,
        "kernel_release": data.get("KERNEL_RELEASE", ""),
        "release_title": data.get("RELEASE_TITLE", ""),
        "ksu_changed": bool_text(ksu_changed),
        "susfs_changed": bool_text(susfs_changed),
        "ksu_latest": ksu_latest,
        "susfs_latest": susfs_latest,
    })

matrix = {"include": include}
text = json.dumps(matrix, separators=(",", ":"))
print(text)
output = os.environ.get("GITHUB_OUTPUT")
if output:
    with open(output, "a", encoding="utf-8") as fh:
        fh.write(f"matrix={text}\n")
        fh.write(f"has_lanes={'true' if include else 'false'}\n")
        fh.write(f"count={len(include)}\n")
PY
