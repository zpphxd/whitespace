import AppKit

// Dev harness: `--render-sample <path>` renders rough shapes to a PNG and exits.
if let idx = CommandLine.arguments.firstIndex(of: "--render-sample"),
   idx + 1 < CommandLine.arguments.count {
    RenderSample.run(to: CommandLine.arguments[idx + 1])
    exit(0)
}
if let idx = CommandLine.arguments.firstIndex(of: "--render-scene"),
   idx + 1 < CommandLine.arguments.count {
    RenderScene.run(to: CommandLine.arguments[idx + 1])
    exit(0)
}
if let idx = CommandLine.arguments.firstIndex(of: "--export-test"),
   idx + 1 < CommandLine.arguments.count {
    ExportTest.run(to: CommandLine.arguments[idx + 1])
    exit(0)
}
if let idx = CommandLine.arguments.firstIndex(of: "--run-cell-test"),
   idx + 1 < CommandLine.arguments.count {
    RunCellTest.run(to: CommandLine.arguments[idx + 1])
    exit(0)
}
if let idx = CommandLine.arguments.firstIndex(of: "--build-arch"),
   idx + 1 < CommandLine.arguments.count {
    ShowcaseBoard.buildAndSave(to: CommandLine.arguments[idx + 1])
    exit(0)
}
if let idx = CommandLine.arguments.firstIndex(of: "--build-demo"),
   idx + 1 < CommandLine.arguments.count {
    DemoBoard.buildAndSave(to: CommandLine.arguments[idx + 1])
    exit(0)
}

// Single-instance guard: a second copy can't register the global hotkeys (the
// first holds them), which looks like "the hotkey stopped working." If another
// instance is already running, hand off to it and exit.
if let bundleID = Bundle.main.bundleIdentifier {
    let mine = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != mine }
    if let existing = others.first {
        existing.activate(options: [.activateAllWindows])
        exit(0)
    }
}

// Entry point. Whitespace is an accessory (menu-bar) app: no Dock icon, no
// standard window — it lives on the desktop layer plus a status-bar item.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
