#!/usr/bin/env bash
# Builds, then installs the app into ~/Applications and both Quick Actions into
# ~/Library/Services — enabled, so nothing has to be switched on in Customize…
set -euo pipefail
cd "$(dirname "$0")/.."

source "$(dirname "$0")/lib.sh"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
SHORTCUT="@^j"   # ⌃⌘J on the instant action; @ command, ^ control, ~ option, $ shift

./scripts/build.sh
./scripts/make-quick-action.sh

mkdir -p "$HOME/Applications" "$HOME/Library/Services"

echo "› installing app"
osascript -e 'quit app id "dev.shykov.imageshrink"' 2>/dev/null || true
rm -rf "$HOME/Applications/Image Shrink.app"
cp -R "build/Image Shrink.app" "$HOME/Applications/"
"$LSREGISTER" -f "$HOME/Applications/Image Shrink.app"

echo "› clearing out earlier installs"
remove_installed_quick_actions
prune_service_prefs
warn_about_other_copies

echo "› installing Quick Actions"
for name in "Convert to JPEG…" "Convert to JPEG Now ⌃⌘J"; do
    cp -R "build/$name.workflow" "$HOME/Library/Services/"
done

# Turning them on here is what saves a trip through Customize… in the Finder menu.
# The key is "<CFBundleIdentifier> - <menu title> - <NSMessage>"; -dict-add keeps
# everyone else's entries. Orphans left behind by uninstall are ignored by macOS.
echo "› enabling them, with ${SHORTCUT} on the instant one"
defaults write pbs NSServicesStatus -dict-add \
    "dev.shykov.imageshrink.quickaction - Convert to JPEG… - runWorkflowAsService" \
    '{"presentation_modes" = {ContextMenu = 1; FinderPreview = 1; ServicesMenu = 1; TouchBar = 0;};}'
defaults write pbs NSServicesStatus -dict-add \
    "dev.shykov.imageshrink.instant - Convert to JPEG Now ⌃⌘J - runWorkflowAsService" \
    "{\"presentation_modes\" = {ContextMenu = 1; FinderPreview = 1; ServicesMenu = 1; TouchBar = 0;}; \"key_equivalent\" = \"${SHORTCUT}\";}"
defaults write pbs ServicesShortcutsPresent -bool true

/System/Library/CoreServices/pbs -flush 2>/dev/null || true
killall Finder 2>/dev/null || true

echo
echo "Installed. Right-click images in Finder → Quick Actions:"
echo "  Convert to JPEG…          opens the window, pick the limit, convert"
echo "  Convert to JPEG Now ⌃⌘J   converts with the last used settings, no window"
echo
echo "Change the shortcut in System Settings → Keyboard → Keyboard Shortcuts → Services."
