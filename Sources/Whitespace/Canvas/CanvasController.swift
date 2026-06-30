import SwiftUI

/// Shared state bridging the SwiftUI tool palette / inspector and the AppKit
/// `CanvasView`. The palette mutates published properties; the canvas reads them
/// at interaction time and reports selection back.
final class CanvasController: ObservableObject {
    @Published var tool: Tool = .select
    @Published var style = CurrentStyle()
    @Published var hasSelection = false

    /// Set by the canvas; invoked by the inspector to push style onto selection.
    var applyStyleToSelection: (() -> Void)?
    var deleteSelection: (() -> Void)?
    var bringSelectionToFront: (() -> Void)?
    var sendSelectionToBack: (() -> Void)?
}
