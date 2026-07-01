import SwiftUI

/// Shared state bridging the SwiftUI tool palette / inspector and the AppKit
/// `CanvasView`. The palette mutates published properties; the canvas reads them
/// at interaction time and reports selection back.
final class CanvasController: ObservableObject {
    @Published var tool: Tool = .select
    @Published var style = CurrentStyle()
    @Published var hasSelection = false
    @Published var selectionCount = 0

    // Tabs (multiple named whiteboards).
    @Published var tabs: [String] = ["Board 1"]
    @Published var currentTab = 0
    var addTab: (() -> Void)?
    var selectTab: ((Int) -> Void)?
    var renameTab: ((Int, String) -> Void)?
    var closeTab: ((Int) -> Void)?
    var moveTab: ((Int, Int) -> Void)?
    var exportTab: ((Int, String) -> Void)?
    var linkFileAction: (() -> Void)?
    var linkURLAction: (() -> Void)?
    var insertImageAction: (() -> Void)?
    var insertCellAction: ((String) -> Void)?
    var insertTestCellAction: (() -> Void)?
    var runGraphAction: (() -> Void)?
    var restartKernelsAction: (() -> Void)?     // drop persistent sessions → fresh state
    var clearBoardAction: (() -> Void)?

    // Settings actions (exposed via the palette gear menu).
    var setEditOpacity: ((CGFloat) -> Void)?
    var setKeepIcons: ((Bool) -> Void)?
    var setLinkColorAction: ((String) -> Void)?
    var setLinkStyleAction: ((String) -> Void)?
    var setStayOnWallpaperAction: ((Bool) -> Void)?
    var openShortcutsAction: (() -> Void)?          // "?" → shortcuts cheat sheet
    var configureHotkeysAction: (() -> Void)?       // rebind the ⌥⌘W / ⌥⌘Q global hotkeys
    // Cross-cutting hooks (wired in AppDelegate).
    var openSearchAction: (() -> Void)?            // Cmd+F: search text across all boards
    var connectVaultAction: (() -> Void)?          // bind the current board to an Obsidian vault
    var focusElementAction: ((String) -> Void)?    // select + center an element by id (search jump)

    /// Set by the canvas; invoked by the inspector to push style onto selection.
    var applyStyleToSelection: (() -> Void)?
    var deleteSelection: (() -> Void)?
    var bringSelectionToFront: (() -> Void)?
    var sendSelectionToBack: (() -> Void)?
    var bringSelectionForward: (() -> Void)?
    var sendSelectionBackward: (() -> Void)?

    /// Type of the current selection (or nil) so the inspector can adapt.
    @Published var selectionType: String?
    var alignAction: ((String) -> Void)?
}
