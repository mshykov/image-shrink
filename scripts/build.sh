#!/usr/bin/env bash
# Builds "Image Shrink.app" into build/ — no Xcode project, just swiftc plus a bundle layout.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Image Shrink.app"
ARCH="$(uname -m)"
DEPLOYMENT_TARGET="13.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "› compiling ($ARCH)"
xcrun swiftc -O -target "${ARCH}-apple-macos${DEPLOYMENT_TARGET}" \
    -o "$APP/Contents/MacOS/ImageShrink" \
    Sources/ImageShrink/*.swift

echo "› icon"
xcrun swift tools/make-icon.swift build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "› signing (ad-hoc)"
codesign --force --sign - "$APP"

echo "built: $APP"
