import AppKit
#if canImport(Sparkle)
import Sparkle
#endif

/// Updates, for the copies that did not come from Homebrew.
///
/// Sparkle is fetched into `vendor/` by `scripts/fetch-sparkle.sh` rather than committed, so a
/// plain checkout builds without it. `canImport` keeps both shapes compiling: with the
/// framework the app checks a signed appcast and installs updates itself, and without it the
/// menu item opens the releases page, which is what every build did before.
@MainActor
enum Updater {
    #if canImport(Sparkle)
    /// Built once, at launch, so the scheduled check runs. A CLI invocation never touches this.
    private static var controller: SPUStandardUpdaterController?

    static var isBuiltIn: Bool { true }

    static func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        Log.write("updater: Sparkle started, feed \(feed)")
    }

    /// Sparkle's own window, including "you are up to date" — which is the answer people are
    /// really asking for, and the reason this does not silently do nothing.
    static func checkForUpdates() {
        start()
        controller?.checkForUpdates(nil)
    }

    private static var feed: String {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "none"
    }
    #else
    static var isBuiltIn: Bool { false }

    static func start() {}

    static func checkForUpdates() {
        NSWorkspace.shared.open(AppDelegate.releases)
    }
    #endif
}
