#!/bin/bash
set -e

APP_NAME="SuperIsland"
APP_EXECUTABLE="SuperIsland"
BUILD_DIR=".build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ICON_CATALOG="Assets.xcassets"
ICON_SOURCE="AppIcon.icon"
ICON_INFO_PLIST=".build/AppIcon.partial.plist"
FALLBACK_ICON_PATH="Sources/SuperIsland/Resources/AppIcon.icns"

echo "Building $APP_NAME (universal)..."
swift build -c release --arch arm64
swift build -c release --arch x86_64

echo "Creating universal binaries..."
ARM_DIR=".build/arm64-apple-macosx/release"
X86_DIR=".build/x86_64-apple-macosx/release"

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Helpers"
mkdir -p "$APP_BUNDLE/Contents/Resources"

lipo -create "$ARM_DIR/$APP_EXECUTABLE" "$X86_DIR/$APP_EXECUTABLE" \
     -output "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"
lipo -create "$ARM_DIR/superisland-bridge" "$X86_DIR/superisland-bridge" \
     -output "$APP_BUNDLE/Contents/Helpers/superisland-bridge"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "Compiling app icon assets..."
if ! xcrun actool \
    --output-format human-readable-text \
    --warnings \
    --errors \
    --notices \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ICON_INFO_PLIST" \
    --compile "$APP_BUNDLE/Contents/Resources" \
    "$ICON_CATALOG" \
    "$ICON_SOURCE"; then
    echo "warning: actool failed, continuing without compiled icon assets"
fi

# Fall back to the prebuilt icns so the app still has an icon when actool is unavailable.
if [ ! -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ] && [ -f "$FALLBACK_ICON_PATH" ]; then
    cp "$FALLBACK_ICON_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Copy the SPM resource bundle into Contents/Resources so the app can be signed.
RESOURCE_BUNDLE=""
for candidate in \
    .build/arm64-apple-macosx/release/SuperIsland_SuperIsland.bundle \
    .build/x86_64-apple-macosx/release/SuperIsland_SuperIsland.bundle \
    .build/arm64-apple-macosx/release/SuperIsland_SuperIsland.bundle \
    .build/x86_64-apple-macosx/release/SuperIsland_SuperIsland.bundle; do
    if [ -d "$candidate" ]; then
        RESOURCE_BUNDLE="$candidate"
        break
    fi
done

if [ -n "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

echo "Ad-hoc code signing..."
if ! codesign --force --sign - "$APP_BUNDLE/Contents/Helpers/superisland-bridge"; then
    echo "warning: helper codesign failed, continuing with unsigned helper"
fi
if ! codesign --force --sign - "$APP_BUNDLE"; then
    echo "warning: app bundle codesign failed, continuing with unsigned app bundle"
fi

echo "Done: $APP_BUNDLE"
echo "Run: open $APP_BUNDLE"
