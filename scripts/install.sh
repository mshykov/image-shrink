#!/usr/bin/env bash
# Builds, then installs the app into ~/Applications and the Quick Action into ~/Library/Services.
set -euo pipefail
cd "$(dirname "$0")/.."

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

./scripts/build.sh
./scripts/make-quick-action.sh

mkdir -p "$HOME/Applications" "$HOME/Library/Services"

echo "› installing app"
osascript -e 'quit app id "dev.shykov.imageshrink"' 2>/dev/null || true
rm -rf "$HOME/Applications/Image Shrink.app"
cp -R "build/Image Shrink.app" "$HOME/Applications/"
"$LSREGISTER" -f "$HOME/Applications/Image Shrink.app"

echo "› installing Quick Action"
rm -rf "$HOME/Library/Services/Convert to JPEG.workflow"
cp -R "build/Convert to JPEG.workflow" "$HOME/Library/Services/"
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo
echo "Installed. Finder → right-click images → Quick Actions → Convert to JPEG."
echo "If the menu entry is missing, log out and back in once so Finder reloads its services."
