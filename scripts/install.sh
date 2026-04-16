#!/usr/bin/env bash

set -euo pipefail

APP_NAME="${APP_NAME:-SuperIsland}"
DEFAULT_MANIFEST_URL="${DEFAULT_MANIFEST_URL:-https://guandata-autotest-report.oss-cn-hangzhou.aliyuncs.com/cdn/superIsland/version.json}"
DEFAULT_TARGET_DIR="${DEFAULT_TARGET_DIR:-/Applications}"

usage() {
  cat <<'EOF'
用法:
  bash scripts/install.sh [dmg路径/下载URL/version.json URL] [目标目录]

示例:
  bash scripts/install.sh
  bash scripts/install.sh https://guandata-autotest-report.oss-cn-hangzhou.aliyuncs.com/cdn/superIsland/SuperIsland.dmg
  bash scripts/install.sh ~/Downloads/SuperIsland.dmg ~/Applications
EOF
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "缺少命令: $command_name" >&2
    exit 1
  fi
}

fetch_manifest_field() {
  local manifest_url="$1"
  local field_name="$2"

  curl -fsSL "$manifest_url" | python3 -c '
import json
import sys

field_name = sys.argv[1]
payload = json.load(sys.stdin)
value = payload.get(field_name)

if not isinstance(value, str) or not value.strip():
    raise SystemExit(f"version.json 缺少有效字段: {field_name}")

print(value.strip(), end="")
' "$field_name"
}

POSITIONAL_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        POSITIONAL_ARGS+=("$1")
        shift
      done
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

if [ "${#POSITIONAL_ARGS[@]}" -gt 2 ]; then
  echo "参数过多，请最多提供 [dmg路径/下载URL/version.json URL] [目标目录]" >&2
  usage
  exit 1
fi

require_command curl
require_command python3
require_command hdiutil
require_command ditto
require_command xattr

SOURCE_INPUT="${POSITIONAL_ARGS[0]:-$DEFAULT_MANIFEST_URL}"
TARGET_DIR="${POSITIONAL_ARGS[1]:-$DEFAULT_TARGET_DIR}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/superisland-install.XXXXXX")"
DOWNLOAD_PATH="$TMP_DIR/${APP_NAME}.dmg"
MOUNT_POINT="$TMP_DIR/mount"
TARGET_APP_PATH="$TARGET_DIR/${APP_NAME}.app"
ATTACHED_DEVICE=""

cleanup() {
  if [ -n "$ATTACHED_DEVICE" ]; then
    hdiutil detach "$ATTACHED_DEVICE" -quiet >/dev/null 2>&1 \
      || hdiutil detach "$MOUNT_POINT" -force -quiet >/dev/null 2>&1 \
      || true
  fi
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

resolve_download_url() {
  local source_input="$1"
  if [[ "$source_input" =~ ^https?:// ]] && [[ "$source_input" == *.json* ]]; then
    fetch_manifest_field "$source_input" "downloadUrl"
    return 0
  fi
  if [[ "$source_input" =~ ^https?:// ]]; then
    printf '%s' "$source_input"
    return 0
  fi
  if [ -f "$source_input" ]; then
    printf '%s' "$source_input"
    return 0
  fi
  echo "找不到安装源: $source_input" >&2
  exit 1
}

run_install_command() {
  if [ -w "$TARGET_DIR" ] && { [ ! -e "$TARGET_APP_PATH" ] || [ -w "$TARGET_APP_PATH" ]; }; then
    "$@"
  else
    sudo "$@"
  fi
}

SOURCE_RESOLVED="$(resolve_download_url "$SOURCE_INPUT")"

if [[ "$SOURCE_RESOLVED" =~ ^https?:// ]]; then
  VERSION="$(fetch_manifest_field "$DEFAULT_MANIFEST_URL" "version" 2>/dev/null || true)"
  if [ -n "$VERSION" ]; then
    echo "准备安装 ${APP_NAME} ${VERSION}"
  else
    echo "准备安装 ${APP_NAME}"
  fi
  echo "下载 DMG: $SOURCE_RESOLVED"
  curl -fsSL "$SOURCE_RESOLVED" -o "$DOWNLOAD_PATH"
else
  echo "使用本地 DMG: $SOURCE_RESOLVED"
  cp "$SOURCE_RESOLVED" "$DOWNLOAD_PATH"
fi

mkdir -p "$MOUNT_POINT"
echo "挂载 DMG..."
ATTACHED_DEVICE="$(
  hdiutil attach -nobrowse -mountpoint "$MOUNT_POINT" "$DOWNLOAD_PATH" \
    | awk '/^\/dev\// { print $1; exit }'
)"

if [ -z "$ATTACHED_DEVICE" ]; then
  echo "挂载 DMG 失败：未拿到磁盘设备信息" >&2
  exit 1
fi

SOURCE_APP_PATH="$(find "$MOUNT_POINT" -maxdepth 2 -name "${APP_NAME}.app" -type d | head -n 1)"
if [ -z "$SOURCE_APP_PATH" ]; then
  echo "在 DMG 中未找到 ${APP_NAME}.app" >&2
  exit 1
fi

echo "安装到: $TARGET_APP_PATH"
run_install_command mkdir -p "$TARGET_DIR"
if [ -e "$TARGET_APP_PATH" ]; then
  run_install_command rm -rf "$TARGET_APP_PATH"
fi
run_install_command ditto "$SOURCE_APP_PATH" "$TARGET_APP_PATH"

# Disk images downloaded from the internet propagate quarantine to the copied app bundle.
# Clearing it here keeps the freshly installed app launchable after script-driven installs.
run_install_command xattr -dr com.apple.quarantine "$TARGET_APP_PATH"

echo
echo "安装完成"
echo "应用位置: $TARGET_APP_PATH"
echo "可直接运行: open \"$TARGET_APP_PATH\""
echo "首次启动如果没有看到界面，可运行: open \"superisland://settings\""
