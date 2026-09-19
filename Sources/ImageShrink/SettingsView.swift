import AppKit
import SwiftUI

/// ⌘, — how the app behaves, as opposed to what one conversion does.
struct SettingsView: View {
    @AppStorage(Settings.notifyKey, store: Settings.defaults) private var notify = true
    @AppStorage(Settings.soundKey, store: Settings.defaults) private var sound = true
    @AppStorage(Settings.instantPresetKey, store: Settings.defaults) private var instantPreset = ""

    var body: some View {
        Form {
            Section("When a conversion finishes") {
                Toggle("Play a sound", isOn: $sound)
                Toggle("Show a notification", isOn: $notify)
                Text("Both apply to runs with no window — the Finder actions. The window "
                     + "shows its own result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Convert to JPEG Now \u{2303}\u{2318}J") {
                Picker("Uses", selection: $instantPreset) {
                    Text("The settings the window used last").tag("")
                    ForEach(Preset.all) { preset in
                        Text("\(preset.name) — \(preset.detail)").tag(preset.id)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Finder actions") {
                Text("Every preset also has its own Quick Action, next to \u{201C}Convert to "
                     + "JPEG\u{2026}\u{201D} and \u{201C}Convert to JPEG Now\u{201D}. Turn "
                     + "individual ones off in Finder \u{2192} right-click \u{2192} Quick "
                     + "Actions \u{2192} Customize\u{2026}")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
