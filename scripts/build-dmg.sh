#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/build-dmg.sh <version>
# Example: ./scripts/build-dmg.sh 1.0.7

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version>" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build"
RELEASE_DIR="$BUILD_DIR/release"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_CONTENT_DIR="$BUILD_DIR/dmg-contents"
APP_NAME="SuperIsland"
APP_EXECUTABLE="SuperIsland"
APP_DIR="$STAGING_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
OUTPUT_DMG="$BUILD_DIR/${APP_NAME}.dmg"
FALLBACK_ICON_PATH="$REPO_ROOT/Sources/SuperIsland/Resources/AppIcon.icns"

echo "==> Building ${APP_NAME} ${VERSION} (universal)"

# Build for both architectures
cd "$REPO_ROOT"
swift build -c release --arch arm64
swift build -c release --arch x86_64

ARM_DIR="$BUILD_DIR/arm64-apple-macosx/release"
X86_DIR="$BUILD_DIR/x86_64-apple-macosx/release"

echo "==> Assembling .app bundle"

# Clean and recreate staging
rm -rf "$STAGING_DIR"
mkdir -p "$CONTENTS_DIR/MacOS"
mkdir -p "$CONTENTS_DIR/Helpers"
mkdir -p "$CONTENTS_DIR/Resources"

# Create universal binaries
lipo -create "$ARM_DIR/$APP_EXECUTABLE" "$X86_DIR/$APP_EXECUTABLE" \
     -output "$CONTENTS_DIR/MacOS/$APP_EXECUTABLE"
lipo -create "$ARM_DIR/superisland-bridge" "$X86_DIR/superisland-bridge" \
     -output "$CONTENTS_DIR/Helpers/superisland-bridge"

# Write Info.plist (use the root Info.plist as base, update version)
CURRENT_VER=$(defaults read "$REPO_ROOT/Info.plist" CFBundleShortVersionString)
sed -e "s/<string>${CURRENT_VER}<\/string>/<string>${VERSION}<\/string>/g" \
    "$REPO_ROOT/Info.plist" > "$CONTENTS_DIR/Info.plist"

# Compile app icon and asset catalog
if ! xcrun actool \
    --output-format human-readable-text \
    --notices --warnings --errors \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist /dev/null \
    --compile "$CONTENTS_DIR/Resources" \
    "$REPO_ROOT/Assets.xcassets" \
    "$REPO_ROOT/AppIcon.icon"; then
    echo "warning: actool failed, continuing without compiled icon assets"
fi

# Fall back to the prebuilt icns so the app still has an icon when actool is unavailable.
if [ ! -f "$CONTENTS_DIR/Resources/AppIcon.icns" ] && [ -f "$FALLBACK_ICON_PATH" ]; then
    cp "$FALLBACK_ICON_PATH" "$CONTENTS_DIR/Resources/AppIcon.icns"
fi

# Copy the SPM resource bundle into Contents/Resources so the packaged app
# stays codesign-friendly. Runtime lookup is handled by AppResourceBundle.
RESOURCE_BUNDLE=""
for candidate in \
    "$BUILD_DIR"/arm64-apple-macosx/release/SuperIsland_SuperIsland.bundle \
    "$BUILD_DIR"/x86_64-apple-macosx/release/SuperIsland_SuperIsland.bundle \
    "$BUILD_DIR"/arm64-apple-macosx/release/SuperIsland_SuperIsland.bundle \
    "$BUILD_DIR"/x86_64-apple-macosx/release/SuperIsland_SuperIsland.bundle; do
    if [ -d "$candidate" ]; then
        RESOURCE_BUNDLE="$candidate"
        break
    fi
done

if [ -n "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$CONTENTS_DIR/Resources/"
fi

echo "==> App bundle assembled at $APP_DIR"

# ---------------------------------------------------------------------------
# Ad-hoc sign the helper and bundle so macOS can launch the locally built app.
# This is not a replacement for Developer ID signing / notarization, but it
# avoids launch constraint failures on newer macOS versions.
# ---------------------------------------------------------------------------
echo "==> Ad-hoc code signing"

if ! codesign --force --sign - "$CONTENTS_DIR/Helpers/superisland-bridge"; then
    echo "warning: helper codesign failed, continuing with unsigned helper"
fi

if ! codesign --deep --force --sign - "$APP_DIR"; then
    echo "warning: app bundle codesign failed, continuing with unsigned app bundle"
fi

echo "==> Creating DMG"

# Remove previous DMG if exists
rm -f "$OUTPUT_DMG"
rm -rf "$DMG_CONTENT_DIR"
mkdir -p "$DMG_CONTENT_DIR"
cp -R "$APP_DIR" "$DMG_CONTENT_DIR/"
ln -s /Applications "$DMG_CONTENT_DIR/Applications"

hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$DMG_CONTENT_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_DMG"

# ---------------------------------------------------------------------------
# Notarization (uncomment after Developer ID signing)
# ---------------------------------------------------------------------------
# BUNDLE_ID="com.superisland.app"
# APPLE_ID="your@apple.id"
# APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"  # app-specific password
#
# xcrun notarytool submit "$OUTPUT_DMG" \
#     --apple-id "$APPLE_ID" \
#     --password "$APP_PASSWORD" \
#     --team-id "$TEAM_ID" \
#     --wait
#
# xcrun stapler staple "$OUTPUT_DMG"
# ---------------------------------------------------------------------------

echo "==> Done: $OUTPUT_DMG"
