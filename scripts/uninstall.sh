#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

osascript -e 'quit app id "dev.shykov.imageshrink"' 2>/dev/null || true

# The app knows what it installed. The shell fallback is for a copy that is already gone.
APP="/Applications/Image Shrink.app"
[ -x "$APP/Contents/MacOS/ImageShrink" ] || APP="$HOME/Applications/Image Shrink.app"
if [ -x "$APP/Contents/MacOS/ImageShrink" ]; then
    "$APP/Contents/MacOS/ImageShrink" --cli --uninstall-services
else
    remove_installed_quick_actions
    prune_service_prefs
fi

rm -rf "/Applications/Image Shrink.app" "$HOME/Applications/Image Shrink.app"
defaults delete dev.shykov.imageshrink 2>/dev/null || true
/System/Library/CoreServices/pbs -flush 2>/dev/null || true
killall Finder 2>/dev/null || true
echo "Removed Image Shrink, its Quick Actions and their settings."
