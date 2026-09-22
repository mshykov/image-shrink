#!/usr/bin/env bash
# Builds the universal, signed, notarised DMG that goes on the releases page, and with
# --publish takes it the rest of the way: tag, GitHub release, Homebrew cask.
#
#   ./scripts/release.sh                  build and notarise, stop there
#   ./scripts/release.sh --publish        …then tag, publish and update the cask
#   ./scripts/release.sh --skip-notarize  a DMG for local testing; Gatekeeper will refuse it
#
# The signing certificate never leaves this Mac — that is why releases are cut here rather than
# on a runner. What a stranger downloads is checked afterwards by CI, in verify-release.yml.
#
# Notarising needs credentials in the keychain once, from an app-specific password or an App
# Store Connect key — never a password in a file:
#   xcrun notarytool store-credentials image-shrink --apple-id <id> --team-id 64HRGLZCS4
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${IMAGESHRINK_NOTARY_PROFILE:-image-shrink}"
NOTARIZE=1
PUBLISH=0
for argument in "$@"; do
    case "$argument" in
        --skip-notarize) NOTARIZE=0 ;;
        --publish) PUBLISH=1 ;;
        *) echo "unknown option $argument" >&2; exit 2 ;;
    esac
done
if [[ "$PUBLISH" -eq 1 && "$NOTARIZE" -eq 0 ]]; then
    echo "refusing: --publish with --skip-notarize would publish what Gatekeeper rejects" >&2
    exit 2
fi

APP="build/Image Shrink.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
DMG="build/ImageShrink-${VERSION}.dmg"
NOTES=""

# Publishing has preconditions worth failing on before a five-minute build.
if [[ "$PUBLISH" -eq 1 ]]; then
    [[ -z "$(git status --porcelain)" ]] || { echo "refusing: the working tree is dirty" >&2; exit 1; }
    git fetch -q origin main
    if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
        echo "refusing: HEAD is not origin/main — a release comes from merged work" >&2
        exit 1
    fi
    # The release notes are the changelog entry. An undated one means the release was never
    # written up, and a release nobody can read is worse than a late one.
    NOTES=$(mktemp)
    trap 'rm -f "$NOTES" "${NOTES}.full"' EXIT
    python3 scripts/changelog-section.py "$VERSION" > "$NOTES"
fi

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

if [[ "$NOTARIZE" -eq 1 ]]; then
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
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Image Shrink" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

IDENTITY="${IMAGESHRINK_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
fi
codesign --force --sign "$IDENTITY" "$DMG"

if [[ "$NOTARIZE" -eq 1 ]]; then
    echo "› notarising the disk image"
    notarize "$DMG"
    # A stapled DMG opens cleanly on a Mac that is offline.
    xcrun stapler staple "$DMG"
fi

echo
echo "› what Gatekeeper sees"
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/  /' || true
[[ "$NOTARIZE" -eq 1 ]] && xcrun stapler validate "$DMG" 2>&1 | sed 's/^/  /'

# The appcast is what installed copies read. It is signed with the EdDSA key in this Mac's
# keychain, travels as a release asset, and is generated after the DMG is final — a signature
# over bytes that later change is worse than none.
APPCAST=""
if [[ -d vendor/sparkle ]]; then
    echo "› appcast"
    python3 scripts/make-appcast.py > build/appcast.xml
    APPCAST="build/appcast.xml"
    echo "  $(grep -o 'sparkle:version>[0-9]*' build/appcast.xml | head -1 | cut -d'>' -f2) signed"
elif [[ "$PUBLISH" -eq 1 ]]; then
    # The feed is releases/latest/download/appcast.xml. A release published without one makes
    # that URL 404, and every installed copy stops hearing about new versions.
    echo "refusing: without vendor/sparkle this release carries no appcast, which strands" >&2
    echo "every installed copy on its current version. Run ./scripts/fetch-sparkle.sh." >&2
    exit 1
else
    echo "› no vendor/sparkle — this build cannot update itself, and publishes no appcast"
fi

echo
echo "$DMG"
echo "  $(du -h "$DMG" | cut -f1)  sha256 $(shasum -a 256 "$DMG" | cut -d' ' -f1)"

if [[ "$PUBLISH" -eq 0 ]]; then
    echo
    echo "Next: ./scripts/release.sh --publish, or attach it to the v${VERSION} release by hand."
    exit 0
fi

echo
echo "› tag v${VERSION}"
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
    echo "  already exists"
else
    git tag -a "v${VERSION}" -m "Image Shrink ${VERSION}"
fi
git push -q origin "v${VERSION}"

echo "› GitHub release"
{
    cat "$NOTES"
    echo
    echo "**Install:** \`brew install --cask mshykov/tap/image-shrink\`, or open the DMG and drag"
    echo "the app to Applications. Open it once — the first launch installs the Finder Quick"
    echo "Actions and the shortcut."
    echo
    echo "macOS 13 or newer · universal (Apple silicon and Intel) · signed with a Developer ID"
    echo "and notarised by Apple."
} > "${NOTES}.full"
assets=("${DMG}#Image Shrink ${VERSION} (universal, notarised)")
[[ -n "$APPCAST" ]] && assets+=("${APPCAST}#Sparkle appcast")
if gh release view "v${VERSION}" >/dev/null 2>&1; then
    gh release upload "v${VERSION}" "$DMG" ${APPCAST:+"$APPCAST"} --clobber
    gh release edit "v${VERSION}" --notes-file "${NOTES}.full"
else
    gh release create "v${VERSION}" "${assets[@]}" \
        --title "Image Shrink ${VERSION}" --notes-file "${NOTES}.full"
fi

echo "› Homebrew cask"
./scripts/update-cask.sh

echo
echo "Published: https://github.com/mshykov/image-shrink/releases/tag/v${VERSION}"
echo "CI checks what a stranger downloads: gh run list --workflow=verify-release.yml"
