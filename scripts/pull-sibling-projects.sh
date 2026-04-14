#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_ROOT_DIR="$(cd "$CURRENT_PROJECT_DIR/.." && pwd)"

ROOT_DIR="${1:-$DEFAULT_ROOT_DIR}"

usage() {
  cat <<EOF
用法:
  bash scripts/pull-sibling-projects.sh [根目录]

说明:
  默认扫描当前项目同级目录下的所有一级子目录，并跳过当前项目自身。
  仅对满足以下条件的 Git 仓库执行更新:
  1. 工作区干净
  2. 当前不在 detached HEAD
  3. 当前分支已配置 upstream

示例:
  bash scripts/pull-sibling-projects.sh
  bash scripts/pull-sibling-projects.sh /Volumes/work/island
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "缺少命令: $name" >&2
    exit 1
  fi
}

is_clean_repo() {
  local repo_dir="$1"
  [[ -z "$(git -C "$repo_dir" status --porcelain --untracked-files=normal)" ]]
}

pull_repo() {
  local repo_dir="$1"
  local repo_name
  local branch_name
  local upstream_name

  repo_name="$(basename "$repo_dir")"

  if ! git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
    echo "[SKIP] $repo_name: 不是 Git 仓库"
    return 0
  fi

  if [ "$repo_dir" = "$CURRENT_PROJECT_DIR" ]; then
    echo "[SKIP] $repo_name: 当前项目"
    return 0
  fi

  if ! is_clean_repo "$repo_dir"; then
    echo "[SKIP] $repo_name: 有未提交改动"
    return 0
  fi

  branch_name="$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [ -z "$branch_name" ]; then
    echo "[SKIP] $repo_name: 当前处于 detached HEAD"
    return 0
  fi

  upstream_name="$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [ -z "$upstream_name" ]; then
    echo "[SKIP] $repo_name: 分支 $branch_name 未配置 upstream"
    return 0
  fi

  echo "[PULL] $repo_name: $branch_name <- $upstream_name"
  if git -C "$repo_dir" pull --ff-only; then
    echo "[ OK ] $repo_name"
  else
    echo "[FAIL] $repo_name: git pull --ff-only 失败"
    return 1
  fi
}

require_command git

if [ ! -d "$ROOT_DIR" ]; then
  echo "目录不存在: $ROOT_DIR" >&2
  exit 1
fi

echo "扫描目录: $ROOT_DIR"
echo "当前项目: $CURRENT_PROJECT_DIR"
echo

success_count=0
skip_count=0
fail_count=0

while IFS= read -r -d '' project_dir; do
  if output="$(pull_repo "$project_dir" 2>&1)"; then
    echo "$output"
    if [[ "$output" == \[PULL\]* ]]; then
      success_count=$((success_count + 1))
    else
      skip_count=$((skip_count + 1))
    fi
  else
    echo "$output"
    fail_count=$((fail_count + 1))
  fi
  echo
done < <(find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

echo "完成"
echo "成功更新: $success_count"
echo "跳过项目: $skip_count"
echo "失败项目: $fail_count"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi
