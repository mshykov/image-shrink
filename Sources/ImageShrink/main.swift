import AppKit

if CommandLine.arguments.contains("--cli") || CommandLine.arguments.contains("--help") {
    exit(CLI.run(arguments: Array(CommandLine.arguments.dropFirst())))
}

// Top-level code is not actor-isolated, but it does run on the main thread.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
}
