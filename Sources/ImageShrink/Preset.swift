import Foundation

/// Named combinations of limit and resolution. This list is the single source of truth:
/// the window, the CLI and the installer that builds one Finder action per preset all
/// read it (`--list-presets`).
struct Preset: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let targetMB: Double
    /// 0 keeps the original resolution.
    let maxDimension: Int

    static let all: [Preset] = [
        Preset(id: "email", name: "Email", targetMB: 2, maxDimension: 0),
        Preset(id: "web", name: "Web", targetMB: 1, maxDimension: 1920),
        Preset(id: "messenger", name: "Messenger", targetMB: 0.5, maxDimension: 1920),
    ]

    static func named(_ id: String) -> Preset? {
        all.first { $0.id == id }
    }

    /// "2 MB", "1 MB · 1920 px"
    var detail: String {
        let size = targetMB < 1
            ? "\(Int(targetMB * 1000)) KB"
            : "\(targetMB.formatted(.number.precision(.fractionLength(0...1)))) MB"
        return maxDimension > 0 ? "\(size) · \(maxDimension) px" : size
    }

    var shortDetail: String {
        targetMB < 1 ? "\(Int(targetMB * 1000)) KB" : "\(targetMB.formatted(.number.precision(.fractionLength(0...1)))) MB"
    }

    /// No parentheses: `defaults` cannot parse a preference key containing them.
    var menuTitle: String { "Convert to JPEG \u{00B7} \(name) \(shortDetail)" }

    func applied(to settings: ConversionSettings) -> ConversionSettings {
        var settings = settings
        settings.targetBytes = Int(targetMB * 1_000_000)
        settings.maxDimension = maxDimension > 0 ? maxDimension : nil
        return settings
    }
}
