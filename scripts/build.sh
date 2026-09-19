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
# -wmo is required for -emit-const-values-path to produce anything, and that file is what
# the App Intents metadata below is extracted from.
xcrun swiftc -O -wmo -target "${ARCH}-apple-macos${DEPLOYMENT_TARGET}" \
    -emit-const-values-path build/const.swiftconstvalues \
    -Xfrontend -const-gather-protocols-file -Xfrontend Resources/appintents-protocols.json \
    -o "$APP/Contents/MacOS/ImageShrink" \
    Sources/ImageShrink/*.swift

echo "› Shortcuts action"
PROCESSOR="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor"
if [ -x "$PROCESSOR" ]; then
    ls Sources/ImageShrink/*.swift > build/sources.txt
    echo "build/const.swiftconstvalues" > build/constvals.txt
    "$PROCESSOR" \
        --output "$APP/Contents/Resources" \
        --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
        --module-name ImageShrink \
        --sdk-root "$(xcrun --show-sdk-path)" \
        --xcode-version "$(xcodebuild -version | tail -1 | awk '{print $3}')" \
        --platform-family macOS \
        --deployment-target "$DEPLOYMENT_TARGET" \
        --target-triple "${ARCH}-apple-macos${DEPLOYMENT_TARGET}" \
        --source-file-list build/sources.txt \
        --swift-const-vals-list build/constvals.txt \
        --quiet-warnings --force >/dev/null
else
    echo "  skipped: no appintentsmetadataprocessor, the Shortcuts action will not appear"
fi

echo "› icon"
xcrun swift tools/make-icon.swift build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp README.md "$APP/Contents/Resources/README.md"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "› signing (ad-hoc)"
codesign --force --sign - "$APP"

echo "built: $APP"
