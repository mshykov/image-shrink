#!/usr/bin/env bash
# Builds, installs the app, and has the app install its own Finder actions — the same path a
# downloaded copy takes on its first launch, so this script tests it rather than bypassing it.
set -euo pipefail
cd "$(dirname "$0")/.."

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# /Applications when the account can write there (admins can), otherwise the user's own.
APP_DIR="${IMAGESHRINK_APP_DIR:-/Applications}"
if [ ! -w "$APP_DIR" ]; then
    echo "note: $APP_DIR is not writable, installing into ~/Applications instead"
    APP_DIR="$HOME/Applications"
fi

./scripts/build.sh

mkdir -p "$APP_DIR"

echo "› installing app into $APP_DIR"
osascript -e 'quit app id "dev.shykov.imageshrink"' 2>/dev/null || true
# Only one copy may exist: the Finder actions call the binary by path.
for old in "/Applications/Image Shrink.app" "$HOME/Applications/Image Shrink.app"; do
    [ "$old" = "$APP_DIR/Image Shrink.app" ] || rm -rf "$old"
done
rm -rf "$APP_DIR/Image Shrink.app"
cp -R "build/Image Shrink.app" "$APP_DIR/"
"$LSREGISTER" -f "$APP_DIR/Image Shrink.app"

echo "› Finder actions"
"$APP_DIR/Image Shrink.app/Contents/MacOS/ImageShrink" --cli --install-services

echo
echo "Installed. Right-click images in Finder → Quick Actions:"
echo "  Convert to JPEG…          opens the window, pick the limit, convert"
echo "  Convert to JPEG Now       converts with the last used settings, no window"
echo "  one per preset            Email 2 MB, Web 1 MB, Messenger 500 KB"
echo
echo "The shortcut is recorded in the app: the banner in the window, or Settings."
echo
codesign -dvv "$APP_DIR/Image Shrink.app" 2>&1 | grep -E "^Authority|^Signature|^TeamIdentifier" || true
