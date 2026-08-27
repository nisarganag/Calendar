#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CalBar"
BUNDLE_ID="com.nisarga.calbar"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "==> Compiling Swift sources..."
mkdir -p "$BUILD_DIR"
swiftc -O -swift-version 5 \
    "$ROOT/Sources/main.swift" \
    "$ROOT/Sources/AppDelegate.swift" \
    "$ROOT/Sources/StatusBarIcon.swift" \
    "$ROOT/Sources/Palette.swift" \
    "$ROOT/Sources/PopoverChrome.swift" \
    "$ROOT/Sources/CalendarViewModel.swift" \
    "$ROOT/Sources/CalendarViews.swift" \
    -o "$BUILD_DIR/$APP_NAME" \

echo "==> Generating app icon..."
swift "$ROOT/Scripts/generate_icon.swift"
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"

echo "==> Bundling $APP_NAME.app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> Ad-hoc code signing..."
codesign --force --sign - --timestamp=none "$APP_DIR"
codesign --verify --strict "$APP_DIR" && echo "    signature OK"

cp -Rf "$APP_DIR" "$ROOT/dist/"
echo "==> Done: $ROOT/dist/$APP_NAME.app"
