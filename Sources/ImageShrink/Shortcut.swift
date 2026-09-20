import AppKit

/// The Finder shortcut, recorded in the app rather than in System Settings.
///
/// A Quick Action's key equivalent lives in the `pbs` preference domain, in the same
/// NSServicesStatus entry that switches the action on, written in Cocoa's old notation:
/// `@` command, `^` control, `~` option, `$` shift, then the character.
struct Shortcut: Equatable, Sendable {
    var keyEquivalent: String

    static let serviceKey = "dev.shykov.imageshrink.instant - Convert to JPEG Now - runWorkflowAsService"
    private static let domain = "pbs" as CFString

    // MARK: - Reading and writing

    static var current: Shortcut? {
        guard let status = CFPreferencesCopyAppValue("NSServicesStatus" as CFString, domain)
                as? [String: Any],
              let entry = status[serviceKey] as? [String: Any],
              let value = entry["key_equivalent"] as? String, !value.isEmpty else { return nil }
        return Shortcut(keyEquivalent: value)
    }

    /// Writes it where pbs looks, then asks pbs to notice.
    static func set(_ shortcut: Shortcut?) {
        var status = CFPreferencesCopyAppValue("NSServicesStatus" as CFString, domain)
            as? [String: Any] ?? [:]
        var entry = status[serviceKey] as? [String: Any] ?? [:]
        if let shortcut {
            entry["key_equivalent"] = shortcut.keyEquivalent
        } else {
            entry.removeValue(forKey: "key_equivalent")
        }
        if entry["presentation_modes"] == nil {
            entry["presentation_modes"] = ["ContextMenu": true, "ServicesMenu": true,
                                           "FinderPreview": true, "TouchBar": false]
        }
        status[serviceKey] = entry
        CFPreferencesSetAppValue("NSServicesStatus" as CFString, status as CFDictionary, domain)
        CFPreferencesSetAppValue("ServicesShortcutsPresent" as CFString, true as CFBoolean, domain)
        CFPreferencesAppSynchronize(domain)
        flush()
    }

    private static func flush() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        process.arguments = ["-flush"]
        try? process.run()
    }

    // MARK: - Recording

    /// Needs a modifier that cannot be typed by accident, and a real key.
    static func from(_ event: NSEvent) -> Shortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) else { return nil }
        guard let characters = event.charactersIgnoringModifiers?.lowercased(),
              let character = characters.first, character.isLetter || character.isNumber else {
            return nil
        }

        var notation = ""
        if flags.contains(.command) { notation += "@" }
        if flags.contains(.control) { notation += "^" }
        if flags.contains(.option) { notation += "~" }
        if flags.contains(.shift) { notation += "$" }
        return Shortcut(keyEquivalent: notation + String(character))
    }

    /// ["⌃", "⌘", "J"] — one cap per key, in the order macOS prints them.
    var caps: [String] {
        var caps: [String] = []
        if keyEquivalent.contains("^") { caps.append("\u{2303}") }
        if keyEquivalent.contains("~") { caps.append("\u{2325}") }
        if keyEquivalent.contains("$") { caps.append("\u{21E7}") }
        if keyEquivalent.contains("@") { caps.append("\u{2318}") }
        if let key = keyEquivalent.last { caps.append(String(key).uppercased()) }
        return caps
    }

    var display: String { caps.joined() }
}
