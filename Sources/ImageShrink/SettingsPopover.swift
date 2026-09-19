import AppKit
import SwiftUI

/// L3 · floating. Everything that is not the limit lives here, one click from the window.
struct SettingsPopover: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.wide) {
            HStack {
                Text("Settings").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Reset") { model.resetSettings() }
                    .buttonStyle(SecondaryButton(compact: true))
            }

            group("Image", footnote: "HEIC and PNG are still rewritten as JPEG \u{2014} only the "
                                   + "resizing is skipped.") {
                row("Longest side") {
                    Picker("Longest side", selection: $model.maxDimension) {
                        Text("Original").tag(0)
                        Text("4096 px").tag(4096)
                        Text("2560 px").tag(2560)
                        Text("1920 px").tag(1920)
                        Text("1280 px").tag(1280)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                Divider().opacity(0.4)
                row("Skip files already small enough") {
                    Toggle("", isOn: $model.skipSmallEnough).labelsHidden().toggleStyle(.switch)
                }
            }

            group("Where files go", footnote: suffixFootnote) {
                row("Save to") {
                    Picker("Save to", selection: $model.destinationMode) {
                        Text("Same folder").tag(DestinationMode.sameFolder)
                        Text("\u{201C}Converted\u{201D} subfolder").tag(DestinationMode.subfolder)
                        Text(model.customDestination?.lastPathComponent ?? "Choose\u{2026}")
                            .tag(DestinationMode.custom)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .onChange(of: model.destinationMode) { mode in
                        if mode == .custom { chooseFolder() }
                    }
                }
                Divider().opacity(0.4)
                row("Name suffix") {
                    TextField("Name suffix", text: $model.suffix, prompt: Text("auto"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                }
            }

            group("Originals", footnote: "These settings are used by the window and by the "
                                       + "Finder shortcut.") {
                row("Keep date created and modified") {
                    Toggle("", isOn: $model.keepDates).labelsHidden().toggleStyle(.switch)
                }
                Divider().opacity(0.4)
                row("Remove metadata (EXIF, GPS)") {
                    Toggle("", isOn: $model.stripMetadata).labelsHidden().toggleStyle(.switch)
                }
                Divider().opacity(0.4)
                row(nil, label: {
                    Label("Move originals to Trash", systemImage: "trash")
                        .font(Theme.control)
                        .foregroundStyle(Theme.destructive)
                }, control: {
                    Toggle("", isOn: $model.replaceOriginals).labelsHidden().toggleStyle(.switch)
                })
            }
        }
        .padding(Theme.wide)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var suffixFootnote: String {
        let typed = model.suffix.trimmingCharacters(in: .whitespaces)
        let example = "IMG_7323\(typed.isEmpty ? ConversionSettings.sizeSuffix(for: 1_900_000) : typed).jpg"
        return typed.isEmpty ? "Auto writes the new size: \(example)" : "Every file becomes \(example)"
    }

    // MARK: - Pieces

    @ViewBuilder
    private func group<Content: View>(_ title: String, footnote: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.tight) {
            Text(title).font(Theme.meta).foregroundStyle(.secondary)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.06)))
            Text(footnote)
                .font(Theme.meta)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row<Control: View>(_ title: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        row(nil, label: { Text(title).font(Theme.control) }, control: control)
    }

    private func row<L: View, Control: View>(_ unused: String?,
                                             @ViewBuilder label: () -> L,
                                             @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: Theme.normal) {
            label()
            Spacer(minLength: Theme.snug)
            control()
        }
        .padding(.horizontal, Theme.normal)
        .padding(.vertical, Theme.snug)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK {
            model.customDestination = panel.url
        } else if model.customDestination == nil {
            model.destinationMode = .sameFolder
        }
    }
}
