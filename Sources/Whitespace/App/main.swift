import AppKit

// Register the bundled hand-drawn font before anything renders text (the dev
// harness flags below render too, so this must come first).
Fonts.registerBundled()

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
if let idx = CommandLine.arguments.firstIndex(of: "--render-stencils"),
   idx + 1 < CommandLine.arguments.count {
    StencilSheet.run(to: CommandLine.arguments[idx + 1])
    exit(0)
}
if let idx = CommandLine.arguments.firstIndex(of: "--render-drop-anim"),
   idx + 1 < CommandLine.arguments.count {
    StencilSheet.renderDropAnimation(to: CommandLine.arguments[idx + 1])
    exit(0)
}
if let idx = CommandLine.arguments.firstIndex(of: "--render-table"),
   idx + 1 < CommandLine.arguments.count {
    StencilSheet.renderTable(to: CommandLine.arguments[idx + 1])
    exit(0)
}
if CommandLine.arguments.contains("--test-bind") {
    // A shape with a centered bound label; probe a point over the label.
    var rect = Element(type: "rectangle", x: 100, y: 100, width: 160, height: 90, seed: 1)
    rect.id = "rect"
    var label = Element(type: "text", x: 130, y: 133, width: 100, height: 24, seed: 2,
                        text: "Server", fontSize: 16)
    label.id = "label"; label.containerId = "rect"
    let els = [rect, label]                         // z-order: rect below, label on top
    let connectable: Set<String> = ["rectangle", "ellipse", "diamond", "text", "image", "cell"]
    let probe = CGPoint(x: 180, y: 145)             // center, over the label
    func pick(skipBoundText: Bool) -> String {
        for e in els.reversed() where connectable.contains(e.type) {
            if skipBoundText && e.type == "text" && e.containerId != nil { continue }
            if e.hitTest(probe, tolerance: 20) { return e.id }
        }
        return "none"
    }
    FileHandle.standardError.write(Data("bind target before fix: \(pick(skipBoundText: false))\n".utf8))
    FileHandle.standardError.write(Data("bind target after  fix: \(pick(skipBoundText: true))\n".utf8))
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
