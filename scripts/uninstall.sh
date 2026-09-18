#!/usr/bin/env bash
set -euo pipefail
osascript -e 'quit app id "dev.shykov.imageshrink"' 2>/dev/null || true
rm -rf "$HOME/Applications/Image Shrink.app"
rm -rf "$HOME/Library/Services/Convert to JPEG.workflow"
defaults delete dev.shykov.imageshrink 2>/dev/null || true
/System/Library/CoreServices/pbs -flush 2>/dev/null || true
echo "Removed Image Shrink and its Quick Action."
