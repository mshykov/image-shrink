import Foundation

/// Preferences that are about the app rather than about one conversion.
enum Settings {
    /// Not a named suite: inside the bundle that is the app's own domain, and macOS refuses
    /// a suite whose name is the bundle identifier.
    static let defaults = UserDefaults.standard

    static let notifyKey = "notifyOnFinish"
    static let soundKey = "soundOnFinish"
    static let instantPresetKey = "instantPreset"

    static var notifyOnFinish: Bool {
        get { defaults.object(forKey: notifyKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: notifyKey) }
    }

    static var soundOnFinish: Bool {
        get { defaults.object(forKey: soundKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: soundKey) }
    }

    /// Empty means the instant action uses whatever the window used last.
    static var instantPreset: String {
        get { defaults.string(forKey: instantPresetKey) ?? "" }
        set { defaults.set(newValue, forKey: instantPresetKey) }
    }
}
