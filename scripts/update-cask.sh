#!/usr/bin/env bash
# Points the Homebrew cask at the release that release.sh just produced.
#
#   ./scripts/release.sh && ./scripts/update-cask.sh
#
# The cask lives in mshykov/homebrew-tap next to the local-review formula, so
# `brew install --cask mshykov/tap/image-shrink` is one command for everyone else. This pushes
# with your own gh credentials; there is no token in CI to leak.
set -euo pipefail
cd "$(dirname "$0")/.."

TAP="${IMAGESHRINK_TAP:-mshykov/homebrew-tap}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="build/ImageShrink-${VERSION}.dmg"

[ -f "$DMG" ] || { echo "no $DMG — run ./scripts/release.sh first" >&2; exit 1; }

# The cask must describe the bytes people actually download, not the ones sitting here.
ASSET="https://github.com/mshykov/image-shrink/releases/download/v${VERSION}/ImageShrink-${VERSION}.dmg"
echo "› checking the published asset"
published=$(mktemp)
trap 'rm -rf "$published" "${WORK:-}"' EXIT
curl -fsSL --proto '=https' --proto-redir '=https' "$ASSET" -o "$published" || {
    echo "the release asset is not published yet: $ASSET" >&2; exit 1; }
local_sum=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
remote_sum=$(shasum -a 256 "$published" | cut -d' ' -f1)
if [ "$local_sum" != "$remote_sum" ]; then
    echo "refusing: the published DMG differs from the local one" >&2
    echo "  local  $local_sum" >&2
    echo "  remote $remote_sum" >&2
    exit 1
fi
echo "  $remote_sum"

WORK=$(mktemp -d)
gh repo clone "$TAP" "$WORK/tap" -- -q
CASK="$WORK/tap/Casks/image-shrink.rb"
[ -f "$CASK" ] || { echo "no cask at $TAP/Casks/image-shrink.rb" >&2; exit 1; }

sed -i '' -E "s/^(  version )\"[^\"]*\"/\1\"${VERSION}\"/" "$CASK"
sed -i '' -E "s/^(  sha256 )\"[^\"]*\"/\1\"${remote_sum}\"/" "$CASK"
ruby -c "$CASK" >/dev/null

cd "$WORK/tap"
if git diff --quiet; then
    echo "the cask already points at ${VERSION}"
    exit 0
fi
git diff --stat
git add Casks/image-shrink.rb
git commit -q -m "Update image-shrink to v${VERSION}"
git push -q origin HEAD
echo "cask updated: brew install --cask ${TAP%%/*}/tap/image-shrink"
