#!/usr/bin/env bash
# Builds "Image Shrink.app" into build/ — no Xcode project, just swiftc plus a bundle layout.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Image Shrink.app"
ARCH="$(uname -m)"
DEPLOYMENT_TARGET="13.0"
# Both architectures for a release, the host's alone for the edit-build-look loop.
ARCHS="${IMAGESHRINK_ARCHS:-$ARCH}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "› compiling ($ARCHS)"
# -wmo is required for -emit-const-values-path to produce anything, and that file is what
# the App Intents metadata below is extracted from. One architecture's copy describes them all.
# Sparkle is optional: ./scripts/fetch-sparkle.sh puts it in vendor/, and the source compiles
# either way behind canImport. Without it the app opens the releases page instead of updating
# itself — which is what a fresh checkout does until someone runs the fetch script.
SPARKLE=""
if [[ -d vendor/sparkle/Sparkle.framework ]]; then
    SPARKLE="vendor/sparkle"
    echo "  with Sparkle $(cat vendor/sparkle/.version)"
fi

slices=()
for arch in $ARCHS; do
    sparkle_flags=()
    if [[ -n "$SPARKLE" ]]; then
        sparkle_flags=(-F "$SPARKLE" -framework Sparkle
                       -Xlinker -rpath -Xlinker "@executable_path/../Frameworks")
    fi
    xcrun swiftc -O -wmo -target "${arch}-apple-macos${DEPLOYMENT_TARGET}" \
        -emit-const-values-path "build/const-${arch}.swiftconstvalues" \
        -Xfrontend -const-gather-protocols-file -Xfrontend Resources/appintents-protocols.json \
        ${sparkle_flags[@]+"${sparkle_flags[@]}"} \
        -o "build/ImageShrink-${arch}" \
        Sources/ImageShrink/*.swift
    slices+=("build/ImageShrink-${arch}")
done
cp "build/const-${ARCHS%% *}.swiftconstvalues" build/const.swiftconstvalues
lipo -create "${slices[@]}" -output "$APP/Contents/MacOS/ImageShrink"

echo "› Shortcuts action"
PROCESSOR="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor"
export_metadata() {
    "$PROCESSOR" \
        --output "$APP/Contents/Resources" \
        --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
        --module-name ImageShrink \
        --sdk-root "$(xcrun --show-sdk-path)" \
        --xcode-version "$(xcodebuild -version | tail -1 | awk '{print $3}')" \
        --platform-family macOS \
        --deployment-target "$DEPLOYMENT_TARGET" \
        --target-triple "${ARCHS%% *}-apple-macos${DEPLOYMENT_TARGET}" \
        --source-file-list build/sources.txt \
        --swift-const-vals-list build/constvals.txt \
        --quiet-warnings --force "$@" >/dev/null 2>&1
}
if [[ -x "$PROCESSOR" ]]; then
    ls Sources/ImageShrink/*.swift > build/sources.txt
    echo "build/const.swiftconstvalues" > build/constvals.txt
    # The processor rejects the parameter summary on some toolchain states — the same sources
    # exported cleanly earlier the same day. Shipping the action without its sentence beats
    # shipping no action, so a refusal falls back instead of failing the build.
    if ! export_metadata; then
        if export_metadata --force-metadata-output; then
            echo "  note: the summary sentence was rejected, the action ships without it"
        else
            echo "  skipped: the export failed, there will be no Shortcuts action"
        fi
    fi
else
    echo "  skipped: no appintentsmetadataprocessor, the Shortcuts action will not appear"
fi

echo "› icon"
xcrun swift tools/make-icon.swift build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp README.md "$APP/Contents/Resources/README.md"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -n "$SPARKLE" ]]; then
    echo "› embedding Sparkle"
    mkdir -p "$APP/Contents/Frameworks"
    rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
    cp -R "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/"
fi

# The Quick Actions travel inside the bundle, with a placeholder where the executable path
# goes — the app writes its own path in when it installs them. They must be in place before
# signing, or they are not covered by the signature. This step runs the binary that was just
# built, so anything it links has to be in the bundle already.
echo "› Finder actions"
# Swallowing this step's output once cost an afternoon: it failed on a clean machine and said
# nothing. Quiet on success, everything it printed on failure.
if ! IMAGESHRINK_BIN='"@IMAGESHRINK_BINARY@"' \
        ./scripts/make-quick-action.sh "$APP/Contents/Resources/Services" > build/quick-actions.log 2>&1; then
    echo "  could not generate them:"
    sed 's/^/    /' build/quick-actions.log
    exit 1
fi

# A personal Developer ID if there is one, ad-hoc otherwise. The work identity is never
# picked: the match is on "Developer ID Application", and IMAGESHRINK_SIGN_IDENTITY wins.
IDENTITY="${IMAGESHRINK_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    # `|| true`, because pipefail turns "no Developer ID in this keychain" into a failed build
    # — which is every contributor's machine and every CI runner, where ad-hoc is the answer.
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
fi
if [[ -n "$IDENTITY" ]]; then
    echo "› signing as $IDENTITY"
    HARDENED=(--options runtime --timestamp)
else
    echo "› signing (ad-hoc, no Developer ID found)"
    IDENTITY="-"
    # An ad-hoc signature carries neither a timestamp nor the hardened runtime; asking for
    # them fails outright rather than degrading.
    HARDENED=()
fi

# Nested code is signed first, from the inside out: notarisation rejects a bundle whose helpers
# are unsigned, and macOS refuses to launch one whose framework was signed after the app around
# it. Versions/Current is a symlink, so the real directory name never has to be guessed.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$FRAMEWORK" ]]; then
    CURRENT="$FRAMEWORK/Versions/Current"
    for nested in "$CURRENT/XPCServices/Downloader.xpc" "$CURRENT/XPCServices/Installer.xpc" \
                  "$CURRENT/Autoupdate" "$CURRENT/Updater.app" "$FRAMEWORK"; do
        [[ -e "$nested" ]] || continue
        codesign --force ${HARDENED[@]+"${HARDENED[@]}"} --sign "$IDENTITY" "$nested"
    done
fi

codesign --force ${HARDENED[@]+"${HARDENED[@]}"} --sign "$IDENTITY" "$APP"

echo "built: $APP"
