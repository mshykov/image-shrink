# Shared bits for install.sh and uninstall.sh.
BUNDLE_PREFIX="dev.shykov.imageshrink"

# Every Quick Action this project ever installed, whatever it was called at the time.
remove_installed_quick_actions() {
    local found=0
    for workflow in "$HOME/Library/Services"/*.workflow; do
        [ -d "$workflow" ] || continue
        local id
        id=$(plutil -extract CFBundleIdentifier raw -o - "$workflow/Contents/Info.plist" 2>/dev/null || true)
        case "$id" in
            "$BUNDLE_PREFIX"*)
                rm -rf "$workflow"
                echo "  removed $(basename "$workflow")"
                found=1
                ;;
        esac
    done
    [ "$found" -eq 1 ] || echo "  nothing to remove"
}

# Stale NSServicesStatus entries outlive a renamed Quick Action and pile up in
# System Settings → Keyboard Shortcuts → Services. export/import keeps everyone else's.
prune_service_prefs() {
    local temporary
    temporary=$(mktemp -t imageshrink-pbs)
    defaults export pbs - | python3 -c '
import plistlib, sys
data = plistlib.loads(sys.stdin.buffer.read())
status = data.get("NSServicesStatus", {})
keep = {k: v for k, v in status.items() if not k.startswith("dev.shykov.imageshrink")}
dropped = len(status) - len(keep)
if dropped:
    data["NSServicesStatus"] = keep
    sys.stderr.write("  dropped %d stale service preference(s)\n" % dropped)
plistlib.dump(data, sys.stdout.buffer)
' > "$temporary"
    defaults import pbs "$temporary"
    rm -f "$temporary"
}

warn_about_other_copies() {
    for candidate in "/Applications/Image Shrink.app" "$HOME/Desktop/Image Shrink.app"; do
        [ -d "$candidate" ] && echo "  note: another copy is at $candidate — delete it by hand if it is stale"
    done
    return 0
}
