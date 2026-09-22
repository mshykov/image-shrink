#!/usr/bin/env bash
# Builds the universal, signed, notarised DMG that goes on the releases page.
#
# Notarising needs credentials in the keychain once, with an app-specific password from
# appleid.apple.com — never a password in a file:
#   xcrun notarytool store-credentials image-shrink --apple-id <id> --team-id 64HRGLZCS4
# Without them, --skip-notarize still produces a DMG for local testing; it is not something
# anyone else's Mac will open without a Gatekeeper warning.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${IMAGESHRINK_NOTARY_PROFILE:-image-shrink}"
NOTARIZE=1
[ "${1:-}" = "--skip-notarize" ] && NOTARIZE=0

APP="build/Image Shrink.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
DMG="build/ImageShrink-${VERSION}.dmg"

echo "› building ${VERSION} (${BUILD}), both architectures"
IMAGESHRINK_ARCHS="arm64 x86_64" ./scripts/build.sh

ARCHS=$(lipo -archs "$APP/Contents/MacOS/ImageShrink")
case "$ARCHS" in
    *arm64*x86_64*|*x86_64*arm64*) echo "  $ARCHS" ;;
    *) echo "refusing: the binary is $ARCHS, Intel Macs could not run it" >&2; exit 1 ;;
esac

# Ad-hoc signatures cannot be notarised, and a missing timestamp is rejected at submission.
SIGNATURE=$(codesign -dvvv "$APP" 2>&1)
case "$SIGNATURE" in
    *"Developer ID Application"*) ;;
    *) echo "refusing: not signed with a Developer ID — notarisation would fail" >&2; exit 1 ;;
esac
case "$SIGNATURE" in
    *Timestamp*) ;;
    *) echo "refusing: no secure timestamp in the signature" >&2; exit 1 ;;
esac
case "$SIGNATURE" in
    *runtime*) ;;
    *) echo "refusing: the hardened runtime is off" >&2; exit 1 ;;
esac

notarize() {
    local target="$1"
    if ! xcrun notarytool submit "$target" --keychain-profile "$PROFILE" --wait; then
        echo >&2
        echo "notarytool could not submit. If the credentials are missing, store them once:" >&2
        echo "  xcrun notarytool store-credentials $PROFILE --apple-id <your-apple-id> --team-id 64HRGLZCS4" >&2
        exit 1
    fi
}

if [ "$NOTARIZE" -eq 1 ]; then
    echo "› notarising the app"
    ditto -c -k --keepParent "$APP" build/ImageShrink.zip
    notarize build/ImageShrink.zip
    xcrun stapler staple "$APP"
    rm -f build/ImageShrink.zip
else
    echo "› skipping notarisation (--skip-notarize)"
fi

echo "› disk image"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Image Shrink" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

IDENTITY="${IMAGESHRINK_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
fi
codesign --force --sign "$IDENTITY" "$DMG"

if [ "$NOTARIZE" -eq 1 ]; then
    echo "› notarising the disk image"
    notarize "$DMG"
    # A stapled DMG opens cleanly on a Mac that is offline.
    xcrun stapler staple "$DMG"
fi

echo
echo "› what Gatekeeper sees"
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/  /' || true
[ "$NOTARIZE" -eq 1 ] && xcrun stapler validate "$DMG" 2>&1 | sed 's/^/  /'

echo
echo "$DMG"
echo "  $(du -h "$DMG" | cut -f1)  sha256 $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo
echo "Next: attach it to the v${VERSION} release, then check it the way a stranger receives it —"
echo "download it in Safari on another Mac or a fresh account, and open it there."
