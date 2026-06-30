import AppKit
import SwiftUI

/// Spotlight-backed file search for the "/" quick-link palette.
@MainActor
final class FileSearchModel: ObservableObject {
    @Published var query = ""
    @Published var results: [String] = []
    private var pending: DispatchWorkItem?

    func search() {
        pending?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        let item = DispatchWorkItem {
            let out = Self.mdfind(q)
            DispatchQueue.main.async { [weak self] in self?.results = out }
        }
        pending = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private static func mdfind(_ q: String) -> [String] {
        let p = Process()
        p.launchPath = "/usr/bin/mdfind"
        p.arguments = ["-name", q]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.terminate()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n").prefix(12).map(String.init)
    }
}

struct FileSearchView: View {
    @ObservedObject var model: FileSearchModel
    @FocusState private var focused: Bool
    var onPick: (String) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search your files to link…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(14)
                .focused($focused)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
                }
                .onChange(of: model.query) { _ in model.search() }
                .onSubmit { if let first = model.results.first { onPick(first) } }
                .onExitCommand { onClose() }

            if !model.results.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.results, id: \.self) { path in
                            Button { onPick(path) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text((path as NSString).lastPathComponent)
                                        Text(path).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 440)
        .liquidGlassPanel(cornerRadius: 16)
    }
}

/// Borderless panel that can become key (so its text field accepts typing).
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class FileSearchWindow {
    private let panel: KeyPanel
    private let model = FileSearchModel()
    var onPick: ((String) -> Void)?

    init() {
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 60),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .modalPanel
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]

        let view = FileSearchView(
            model: model,
            onPick: { [weak self] path in self?.onPick?(path); self?.hide() },
            onClose: { [weak self] in self?.hide() })
        panel.contentViewController = NSHostingController(rootView: view)
    }

    func show() {
        model.query = ""
        model.results = []
        panel.layoutIfNeeded()
        if let screen = NSScreen.main {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                                         y: screen.frame.midY + 120))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel.orderOut(nil) }
}
