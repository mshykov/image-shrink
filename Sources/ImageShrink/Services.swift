import AppKit

/// The Finder Quick Actions, installed by the app itself rather than by a script — a
/// downloaded app has no repository to run one from.
///
/// The templates ship inside the bundle with `@IMAGESHRINK_BINARY@` where the executable path
/// belongs, because a Quick Action calls the app by path and a download can sit anywhere. They
/// are copied into `~/Library/Services` and switched on in the `pbs` preference domain, which
/// is what saves everyone a trip through Customize….
enum Services {
    static let prefix = "dev.shykov.imageshrink"
    static let instantIdentifier = prefix + ".instant"
    static let defaultShortcut = Shortcut(keyEquivalent: "@^j")

    private static let placeholder = "@IMAGESHRINK_BINARY@"
    private static let domain = "pbs" as CFString
    private static let stampKey = "installedServices"

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services", isDirectory: true)
    }

    /// Empty when the app was built without them — the dev binary in `build/`, for instance.
    static var templates: [URL] {
        guard let root = Bundle.main.resourceURL?
            .appendingPathComponent("Services", isDirectory: true),
              let entries = try? FileManager.default
                .contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return entries.filter { $0.pathExtension == "workflow" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A finished install is this build, from this copy of the app: a second copy in another
    /// folder would leave the actions pointing at the one that is no longer there.
    private static var signature: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) \(executable)"
    }

    private static var executable: String {
        Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    }

    static var needsInstall: Bool {
        guard !templates.isEmpty else { return false }
        let present = templates.allSatisfy {
            FileManager.default.fileExists(atPath:
                folder.appendingPathComponent($0.lastPathComponent).path)
        }
        return !present || UserDefaults.standard.string(forKey: stampKey) != signature
    }

    // MARK: - Installing

    /// Returns how many actions ended up installed. Replaces whatever was there, so it doubles
    /// as the repair path: a stale action under an old name is removed, not left behind.
    @discardableResult
    static func install() -> Int {
        let manager = FileManager.default
        let shortcut = Shortcut.current ?? defaultShortcut
        removeInstalled()
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)

        var status = preferences().filter { !$0.key.hasPrefix(prefix) }
        var installed = 0
        for template in templates {
            let destination = folder.appendingPathComponent(template.lastPathComponent)
            do {
                try manager.copyItem(at: template, to: destination)
            } catch {
                Log.write("services: could not install \(template.lastPathComponent): \(error)")
                continue
            }
            point(destination, at: executable)
            guard let (identifier, title) = describe(destination) else { continue }
            var entry: [String: Any] = ["presentation_modes": ["ContextMenu": true,
                                                               "ServicesMenu": true,
                                                               "FinderPreview": true,
                                                               "TouchBar": false]]
            if identifier == instantIdentifier { entry["key_equivalent"] = shortcut.keyEquivalent }
            status["\(identifier) - \(title) - runWorkflowAsService"] = entry
            installed += 1
        }

        write(status)
        UserDefaults.standard.set(signature, forKey: stampKey)
        Log.write("services: installed \(installed) into \(folder.path)")
        return installed
    }

    static func uninstall() {
        removeInstalled()
        write(preferences().filter { !$0.key.hasPrefix(prefix) })
        UserDefaults.standard.removeObject(forKey: stampKey)
        Log.write("services: removed")
    }

    /// Finder reads its services list once; without this the menu is right only after a login.
    static func restartFinder() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        try? process.run()
    }

    // MARK: - Pieces

    /// Every action this project ever installed, whatever it was called at the time.
    private static func removeInstalled() {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: folder,
                                                             includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.pathExtension == "workflow" {
            guard let (identifier, _) = describe(entry), identifier.hasPrefix(prefix) else { continue }
            try? manager.removeItem(at: entry)
        }
    }

    private static func describe(_ workflow: URL) -> (identifier: String, title: String)? {
        guard let info = NSDictionary(contentsOf: workflow
            .appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let identifier = info["CFBundleIdentifier"] as? String,
              let services = info["NSServices"] as? [[String: Any]],
              let item = services.first?["NSMenuItem"] as? [String: Any],
              let title = item["default"] as? String else { return nil }
        return (identifier, title)
    }

    /// Swaps the placeholder in the shell action for the path this app actually runs from.
    private static func point(_ workflow: URL, at binary: String) {
        let document = workflow.appendingPathComponent("Contents/document.wflow")
        guard let data = try? Data(contentsOf: document),
              var plist = try? PropertyListSerialization
                .propertyList(from: data, format: nil) as? [String: Any],
              var actions = plist["actions"] as? [[String: Any]], !actions.isEmpty,
              var action = actions[0]["action"] as? [String: Any],
              var parameters = action["ActionParameters"] as? [String: Any],
              let command = parameters["COMMAND_STRING"] as? String,
              command.contains(placeholder) else { return }
        parameters["COMMAND_STRING"] = command.replacingOccurrences(of: placeholder, with: binary)
        action["ActionParameters"] = parameters
        actions[0]["action"] = action
        plist["actions"] = actions
        guard let updated = try? PropertyListSerialization
            .data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? updated.write(to: document)
    }

    private static func preferences() -> [String: Any] {
        CFPreferencesCopyAppValue("NSServicesStatus" as CFString, domain) as? [String: Any] ?? [:]
    }

    private static func write(_ status: [String: Any]) {
        CFPreferencesSetAppValue("NSServicesStatus" as CFString, status as CFDictionary, domain)
        CFPreferencesSetAppValue("ServicesShortcutsPresent" as CFString, true as CFBoolean, domain)
        CFPreferencesAppSynchronize(domain)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        process.arguments = ["-flush"]
        try? process.run()
    }
}
