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
for workflow in build/*.workflow; do
    cp -R "$workflow" "$HOME/Library/Services/"
    echo "  $(basename "${workflow%.workflow}")"
done

# Turning them on here is what saves a trip through Customize… in the Finder menu. The key
# is "<CFBundleIdentifier> - <menu title> - <NSMessage>", read back from each workflow so a
# renamed or new action cannot fall out of step. -dict-add keeps everyone else's entries.
echo "› enabling them, with ${SHORTCUT} on the instant one"
modes='"presentation_modes" = {ContextMenu = 1; FinderPreview = 1; ServicesMenu = 1; TouchBar = 0;};'
for workflow in "$HOME/Library/Services"/*.workflow; do
    plist="$workflow/Contents/Info.plist"
    identifier=$(plutil -extract CFBundleIdentifier raw -o - "$plist" 2>/dev/null) || continue
    case "$identifier" in "$BUNDLE_PREFIX"*) ;; *) continue ;; esac
    title=$(plutil -extract NSServices.0.NSMenuItem.default raw -o - "$plist")
    key="$identifier - $title - runWorkflowAsService"
    if [ "$identifier" = "dev.shykov.imageshrink.instant" ]; then
        defaults write pbs NSServicesStatus -dict-add "$key" "{${modes} \"key_equivalent\" = \"${SHORTCUT}\";}"
    else
        defaults write pbs NSServicesStatus -dict-add "$key" "{${modes}}"
    fi
done
defaults write pbs ServicesShortcutsPresent -bool true

/System/Library/CoreServices/pbs -flush 2>/dev/null || true
killall Finder 2>/dev/null || true

echo
echo "Installed. Right-click images in Finder → Quick Actions:"
echo "  Convert to JPEG…          opens the window, pick the limit, convert"
echo "  Convert to JPEG Now ⌃⌘J   converts with the last used settings, no window"
echo "  one per preset            Email 2 MB, Web 1 MB, Messenger 500 KB"
echo
echo "Change the shortcut in System Settings → Keyboard → Keyboard Shortcuts → Services."
