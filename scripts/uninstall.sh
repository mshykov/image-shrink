#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

osascript -e 'quit app id "dev.shykov.imageshrink"' 2>/dev/null || true
rm -rf "$HOME/Applications/Image Shrink.app"
remove_installed_quick_actions
prune_service_prefs
defaults delete dev.shykov.imageshrink 2>/dev/null || true
/System/Library/CoreServices/pbs -flush 2>/dev/null || true
killall Finder 2>/dev/null || true
echo "Removed Image Shrink, its Quick Actions and their settings."
