import SwiftUI
import UniformTypeIdentifiers

/// Excalidraw-style top toolbar: just the tools row, centered at the top of the
/// screen. Primary tool buttons plus the image, link, and "more tools" menus.
/// Everything binds to `CanvasController`.
struct TopToolbarView: View {
    @ObservedObject var controller: CanvasController

    var body: some View {
        tools
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .liquidGlassPanel(cornerRadius: 18)
    }

    private var tools: some View {
        HStack(spacing: 2) {
            ForEach(Tool.primary, id: \.self) { tool in
                Button {
                    controller.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 24, height: 26)
                        .background(controller.tool == tool ? Color(hex: 0x6965db) : .clear)
                        .foregroundStyle(controller.tool == tool ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("\(tool.rawValue.capitalized) (\(String(tool.key)))")
            }
            Divider().frame(height: 18).padding(.horizontal, 1)
            Button { controller.insertImageAction?() } label: {
                Image(systemName: "photo").frame(width: 25, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("Insert image")
            Menu {
                Button("Link File or Folder…") { controller.linkFileAction?() }
                Button("Link URL…") { controller.linkURLAction?() }
            } label: {
                Image(systemName: "paperclip").frame(width: 25, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Link a file, folder, or URL")

            Menu {
                Button { controller.tool = .frame } label: { Label(Tool.frame.label, systemImage: Tool.frame.symbol) }
                Button { controller.tool = .laser } label: { Label(Tool.laser.label, systemImage: Tool.laser.symbol) }
                Button { controller.tool = .lasso } label: { Label(Tool.lasso.label, systemImage: Tool.lasso.symbol) }
                Divider()
                Menu {
                    Button("Shell") { controller.insertCellAction?("shell") }
                    Button("Python") { controller.insertCellAction?("python") }
                    Button("JavaScript") { controller.insertCellAction?("javascript") }
                    Button("Ruby") { controller.insertCellAction?("ruby") }
                } label: { Label("Code Cell", systemImage: "chevron.left.forwardslash.chevron.right") }
                Button { controller.runGraphAction?() } label: { Label("Run Graph (⌘⇧↵)", systemImage: "play.circle") }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 25, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More tools")
        }
    }
}
