#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST_PATH="$ROOT_DIR/Info.plist"
SETTINGS_PATH="$ROOT_DIR/Sources/SuperIsland/Settings.swift"
BUILD_SCRIPT_PATH="$ROOT_DIR/scripts/build-dmg.sh"
INSTALLER_SCRIPT_PATH="$ROOT_DIR/scripts/install.sh"
DIST_DIR="$ROOT_DIR/dist"
OSSUTIL_BIN="${OSSUTIL_BIN:-ossutil}"
APP_NAME="${APP_NAME:-SuperIsland}"
PACKAGE_PREFIX="${PACKAGE_PREFIX:-$APP_NAME}"
DEFAULT_OSS_DEST="oss://guandata-autotest-report/cdn/superIsland"
DEFAULT_OSS_PUBLIC_BASE_URL="https://guandata-autotest-report.oss-cn-hangzhou.aliyuncs.com/cdn/superIsland"
OSS_DEST="${OSS_DEST:-$DEFAULT_OSS_DEST}"
OSS_PUBLIC_BASE_URL="${OSS_PUBLIC_BASE_URL:-$DEFAULT_OSS_PUBLIC_BASE_URL}"
RELEASE_NOTES="${RELEASE_NOTES:-}"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "缺少命令: $command_name" >&2
    exit 1
  fi
}

prompt_version_bump() {
  local current_version="$1"
  local input_stream="/dev/tty"
  local choice=""

  if [ ! -r "$input_stream" ]; then
    if [ -t 0 ]; then
      input_stream="/dev/stdin"
    else
      echo "当前环境不支持交互式选择版本类型，请显式传入 patch/minor/major。" >&2
      exit 1
    fi
  fi

  while true; do
    printf '当前版本: %s\n' "$current_version" >&2
    printf '请选择发版类型 [patch/minor/major] (默认: patch): ' >&2
    IFS= read -r choice < "$input_stream"
    choice="${choice:-patch}"

    case "$choice" in
      patch|minor|major)
        printf '%s' "$choice"
        return 0
        ;;
      *)
        echo "请输入 patch、minor 或 major。" >&2
        ;;
    esac
  done
}

require_command "$OSSUTIL_BIN"
require_command python3
require_command /usr/libexec/PlistBuddy

CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_PATH")"
VERSION_INPUT="${1:-${RELEASE_VERSION:-}}"
BUMP_TYPE=""

if [ -z "$VERSION_INPUT" ]; then
  BUMP_TYPE="$(prompt_version_bump "$CURRENT_VERSION")"
elif [[ "$VERSION_INPUT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  VERSION="$VERSION_INPUT"
else
  BUMP_TYPE="$VERSION_INPUT"
fi

if [ -z "${VERSION:-}" ]; then
  case "$BUMP_TYPE" in
    patch|minor|major)
      ;;
    *)
      echo "未知的版本类型: $BUMP_TYPE，请使用 patch、minor、major 或直接传入 0.0.1 这种版本号。" >&2
      exit 1
      ;;
  esac

  VERSION="$(CURRENT_VERSION="$CURRENT_VERSION" BUMP_TYPE="$BUMP_TYPE" python3 <<'PY'
import os

current = os.environ["CURRENT_VERSION"]
bump_type = os.environ["BUMP_TYPE"]
parts = current.split(".")
if len(parts) != 3 or not all(part.isdigit() for part in parts):
    raise SystemExit(f"不支持的版本号格式: {current}")

major, minor, patch = map(int, parts)

if bump_type == "patch":
    patch += 1
elif bump_type == "minor":
    minor += 1
    patch = 0
elif bump_type == "major":
    major += 1
    minor = 0
    patch = 0
else:
    raise SystemExit(f"未知的版本类型: {bump_type}")

print(f"{major}.{minor}.{patch}", end="")
PY
)"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST_PATH"

python3 - "$SETTINGS_PATH" "$VERSION" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
content = path.read_text(encoding="utf-8")
updated, count = re.subn(
    r'(static let fallback = ")[^"]+(")',
    rf'\g<1>{version}\2',
    content,
    count=1,
)
if count != 1:
    raise SystemExit("未找到 AppVersion.fallback，无法同步版本号。")
path.write_text(updated, encoding="utf-8")
PY

if [ -z "$RELEASE_NOTES" ] && "$ROOT_DIR/scripts/extract-changelog.sh" "$VERSION" >/dev/null 2>&1; then
  RELEASE_NOTES="$("$ROOT_DIR/scripts/extract-changelog.sh" "$VERSION")"
fi

"$BUILD_SCRIPT_PATH" "$VERSION"

LOCAL_DMG_SOURCE="$ROOT_DIR/.build/${APP_NAME}.dmg"
PACKAGE_DMG="$DIST_DIR/${PACKAGE_PREFIX}.dmg"
VERSION_JSON="$DIST_DIR/version.json"
INSTALLER_SCRIPT_DIST="$DIST_DIR/install.sh"
REMOTE_VERSION_JSON_CACHE="$DIST_DIR/remote-version.json"
PREVIOUS_PACKAGE_DMG="$DIST_DIR/${PACKAGE_PREFIX}-previous.dmg"
DOWNLOAD_URL="${OSS_PUBLIC_BASE_URL%/}/${PACKAGE_PREFIX}-${VERSION}.dmg"
RELEASE_URL="${RELEASE_URL:-$DOWNLOAD_URL}"
INSTALLER_URL="${OSS_PUBLIC_BASE_URL%/}/install.sh"
REMOTE_BASE="${OSS_DEST%/}"
REMOTE_PACKAGE_PATH="$REMOTE_BASE/${PACKAGE_PREFIX}.dmg"
VERSIONED_REMOTE_PACKAGE_PATH="$REMOTE_BASE/${PACKAGE_PREFIX}-${VERSION}.dmg"
REMOTE_VERSION_JSON_PATH="$REMOTE_BASE/version.json"
REMOTE_INSTALLER_PATH="$REMOTE_BASE/install.sh"
ARCHIVED_REMOTE_PACKAGE_PATH=""
PREVIOUS_VERSION=""

if [ ! -f "$LOCAL_DMG_SOURCE" ]; then
  echo "找不到构建产物: $LOCAL_DMG_SOURCE" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
cp "$LOCAL_DMG_SOURCE" "$PACKAGE_DMG"
cp "$INSTALLER_SCRIPT_PATH" "$INSTALLER_SCRIPT_DIST"
chmod +x "$INSTALLER_SCRIPT_DIST"
rm -f "$VERSION_JSON" "$REMOTE_VERSION_JSON_CACHE" "$PREVIOUS_PACKAGE_DMG"

cleanup() {
  rm -f "$REMOTE_VERSION_JSON_CACHE" "$PREVIOUS_PACKAGE_DMG"
}

trap cleanup EXIT

if "$OSSUTIL_BIN" cp "$REMOTE_VERSION_JSON_PATH" "$REMOTE_VERSION_JSON_CACHE" >/dev/null 2>&1; then
  PREVIOUS_VERSION="$(python3 - "$REMOTE_VERSION_JSON_CACHE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    payload = json.load(fh)

version = str(payload.get("version", "")).strip()
if not version:
    raise SystemExit("线上 version.json 缺少有效的 version 字段。")

print(version, end="")
PY
)"

  if "$OSSUTIL_BIN" cp "$REMOTE_PACKAGE_PATH" "$PREVIOUS_PACKAGE_DMG" >/dev/null 2>&1; then
    ARCHIVED_REMOTE_PACKAGE_PATH="$REMOTE_BASE/${PACKAGE_PREFIX}-${PREVIOUS_VERSION}.dmg"
    "$OSSUTIL_BIN" cp -f "$PREVIOUS_PACKAGE_DMG" "$ARCHIVED_REMOTE_PACKAGE_PATH" >/dev/null
  else
    echo "警告：已读取到线上旧版本 ${PREVIOUS_VERSION}，但未找到当前 DMG，跳过旧包归档。" >&2
  fi
fi

VERSION="$VERSION" \
DOWNLOAD_URL="$DOWNLOAD_URL" \
RELEASE_URL="$RELEASE_URL" \
INSTALLER_URL="$INSTALLER_URL" \
RELEASE_NOTES="$RELEASE_NOTES" \
VERSION_JSON="$VERSION_JSON" \
python3 <<'PY'
import json
import os
from pathlib import Path

payload = {
    "version": os.environ["VERSION"],
    "downloadUrl": os.environ["DOWNLOAD_URL"],
    "releaseUrl": os.environ["RELEASE_URL"],
    "installerUrl": os.environ["INSTALLER_URL"],
    "publishedAt": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat().replace("+00:00", "Z"),
    "notes": os.environ.get("RELEASE_NOTES", ""),
}

Path(os.environ["VERSION_JSON"]).write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

"$OSSUTIL_BIN" cp -f "$PACKAGE_DMG" "$REMOTE_PACKAGE_PATH"
"$OSSUTIL_BIN" cp -f "$PACKAGE_DMG" "$VERSIONED_REMOTE_PACKAGE_PATH"
"$OSSUTIL_BIN" cp -f "$VERSION_JSON" "$REMOTE_VERSION_JSON_PATH"
"$OSSUTIL_BIN" cp -f "$INSTALLER_SCRIPT_DIST" "$REMOTE_INSTALLER_PATH"

echo "发布完成"
if [ -n "$BUMP_TYPE" ]; then
  echo "  版本升级: $CURRENT_VERSION -> $VERSION ($BUMP_TYPE)"
else
  echo "  版本设置: $CURRENT_VERSION -> $VERSION"
fi
echo "  本地 DMG: $PACKAGE_DMG"
echo "  本地版本清单: $VERSION_JSON"
echo "  本地安装脚本: $INSTALLER_SCRIPT_DIST"
if [ -n "$ARCHIVED_REMOTE_PACKAGE_PATH" ]; then
  echo "  已归档旧版本包: $ARCHIVED_REMOTE_PACKAGE_PATH"
fi
echo "  线上 DMG: $REMOTE_PACKAGE_PATH"
echo "  线上版本归档: $VERSIONED_REMOTE_PACKAGE_PATH"
echo "  线上版本清单: $REMOTE_VERSION_JSON_PATH"
echo "  线上安装脚本: $REMOTE_INSTALLER_PATH"
echo "  下载地址: $DOWNLOAD_URL"
echo "  安装命令: curl -fsSL $INSTALLER_URL | bash"
