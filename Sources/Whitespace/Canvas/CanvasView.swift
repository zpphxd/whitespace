import AppKit

/// The drawing surface: renders the scene under the camera and handles all
/// pointer/keyboard interaction (create, select, move, resize, pan, zoom).
final class CanvasView: NSView {

    let scene: Scene
    let controller: CanvasController
    private let renderer = ElementRenderer()
    private var camera = Camera()

    var isEditing = false {
        didSet { needsDisplay = true; if !isEditing { commitText() } }
    }

    /// Called after any scene mutation so the app can schedule an autosave.
    var onSceneChange: (() -> Void)?

    /// Called when "/" is pressed — opens the file-link search palette.
    var onSlashSearch: (() -> Void)?

    /// Called when a `.excalidraw` file is dropped/opened — load it as a board.
    var onOpenFile: ((URL) -> Void)?

    /// Whiteboard backdrop opacity per mode (1 = opaque white, 0 = wallpaper
    /// shows through). Defaults: idle is transparent so the desktop looks
    /// normal with drawings floating on it; edit mode shows a light board.
    /// Both are user-configurable via `Settings`.
    var idleBoardOpacity: CGFloat = Settings.idleBoardOpacity
    var editBoardOpacity: CGFloat = Settings.editBoardOpacity

    // Interaction state
    private enum Drag {
        case none
        case create(id: String)
        case line(id: String)
        case freedraw(id: String)
        case move(origins: [String: CGPoint])
        case resize(id: String, handle: Handle, start: CGRect)
        case endpoint(id: String, isStart: Bool, otherAbs: CGPoint)
        case marquee(startScene: CGPoint)
        case pan
    }
    private var drag: Drag = .none
    private var dragStart: CGPoint = .zero
    private var lastPanPoint: CGPoint = .zero
    private var spaceDown = false
    private var marqueeRect: CGRect?

    private var textField: NSTextField?
    private var editingTextId: String?
    private var clipboard: [Element] = []

    init(frame: NSRect, scene: Scene, controller: CanvasController) {
        self.scene = scene
        self.controller = controller
        super.init(frame: frame)
        scene.onChange = { [weak self] in
            self?.needsDisplay = true
            self?.onSceneChange?()
        }
        registerForDraggedTypes([.fileURL])
        wireController()
    }

    // MARK: Drag-and-drop (files / .excalidraw)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isEditing ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              !urls.isEmpty else { return false }
        let scenePt = camera.viewToScene(convert(sender.draggingLocation, from: nil))
        for (i, url) in urls.enumerated() {
            let p = CGPoint(x: scenePt.x, y: scenePt.y + CGFloat(i) * 28)
            if url.pathExtension.lowercased() == "excalidraw" {
                onOpenFile?(url)
            } else {
                addLink(link: url.path, name: url.lastPathComponent, at: p)
            }
        }
        return true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEditing }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func wireController() {
        controller.applyStyleToSelection = { [weak self] in self?.applyStyleToSelection() }
        controller.deleteSelection = { [weak self] in self?.deleteSelectionAction() }
        controller.bringSelectionToFront = { [weak self] in
            guard let self else { return }
            self.scene.beginEdit()
            self.scene.selection.forEach { self.scene.bringToFront($0) }
        }
        controller.sendSelectionToBack = { [weak self] in
            guard let self else { return }
            self.scene.beginEdit()
            self.scene.selection.forEach { self.scene.sendToBack($0) }
        }
        controller.bringSelectionForward = { [weak self] in
            guard let self else { return }
            self.scene.beginEdit()
            self.scene.selection.forEach { self.scene.bringForward($0) }
        }
        controller.sendSelectionBackward = { [weak self] in
            guard let self else { return }
            self.scene.beginEdit()
            self.scene.selection.forEach { self.scene.sendBackward($0) }
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Whiteboard backdrop — transparent when idle by default.
        let boardOpacity = isEditing ? editBoardOpacity : idleBoardOpacity
        if boardOpacity > 0 {
            ctx.setFillColor(NSColor.white.withAlphaComponent(boardOpacity).cgColor)
            ctx.fill(bounds)
        }

        renderer.draw(scene: scene, camera: camera, in: ctx)

        drawSelection(in: ctx)
        drawMarquee(in: ctx)
        drawEditBorder(in: ctx)
    }

    private func drawEditBorder(in ctx: CGContext) {
        guard isEditing else { return }
        let inset = bounds.insetBy(dx: 3, dy: 3)
        ctx.setStrokeColor(NSColor(hex: 0x6965db).withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(3)
        ctx.stroke(inset)
    }

    private func selectionBounds() -> CGRect? {
        let sel = scene.elements.filter { scene.selection.contains($0.id) }
        guard let first = sel.first else { return nil }
        return sel.dropFirst().reduce(first.boundingRect) { $0.union($1.boundingRect) }
    }

    private func drawSelection(in ctx: CGContext) {
        guard isEditing, let bounds = selectionBounds() else { return }

        // Single line/arrow: show draggable endpoint handles instead of a box.
        if scene.selection.count == 1,
           let e = scene.element(scene.selection.first!),
           e.type == "line" || e.type == "arrow" {
            ctx.setStrokeColor(NSColor(hex: 0x6965db).cgColor)
            ctx.setLineWidth(1.5)
            for pt in [e.absolutePoints.first, e.absolutePoints.last].compactMap({ $0 }) {
                let v = camera.sceneToView(pt)
                let hr = CGRect(x: v.x - 5, y: v.y - 5, width: 10, height: 10)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: hr)
                ctx.strokeEllipse(in: hr)
            }
            return
        }

        let r = viewRect(bounds).insetBy(dx: -4, dy: -4)
        ctx.setStrokeColor(NSColor(hex: 0x6965db).cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(r)
        // Resize handles (single selection only).
        if scene.selection.count == 1 {
            for h in Handle.allCases {
                let hr = handleRect(h, in: r)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(hr)
                ctx.setStrokeColor(NSColor(hex: 0x6965db).cgColor)
                ctx.stroke(hr)
            }
        }
    }

    private func drawMarquee(in ctx: CGContext) {
        guard let m = marqueeRect else { return }
        let r = viewRect(m)
        ctx.setFillColor(NSColor(hex: 0x6965db, alpha: 0.08).cgColor)
        ctx.fill(r)
        ctx.setStrokeColor(NSColor(hex: 0x6965db).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(r)
    }

    // MARK: Coordinate helpers

    private func viewPoint(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }
    private func scenePoint(_ e: NSEvent) -> CGPoint { camera.viewToScene(viewPoint(e)) }
    private func viewRect(_ scene: CGRect) -> CGRect {
        let o = camera.sceneToView(scene.origin)
        return CGRect(x: o.x, y: o.y, width: scene.width * camera.zoom, height: scene.height * camera.zoom)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard isEditing else { return }
        window?.makeFirstResponder(self)
        commitText()
        let p = scenePoint(event)

        // Double-click: open a linked element, edit a text element, or start a
        // new text box on empty canvas.
        if event.clickCount == 2 {
            if let hit = scene.hitTest(p, tolerance: 8 / camera.zoom) {
                if let link = hit.link, !link.isEmpty { openLink(link); return }
                if hit.type == "text" { beginEditingText(hit); return }
            }
            beginText(at: p)
            return
        }

        dragStart = p
        lastPanPoint = viewPoint(event)

        if spaceDown { drag = .pan; return }

        let tool = controller.tool
        if tool == .select {
            beginSelectInteraction(at: p, viewPt: viewPoint(event), shift: event.modifierFlags.contains(.shift))
        } else if tool == .text {
            beginText(at: p)
        } else if tool == .freedraw {
            beginFreedraw(at: p)
        } else if tool == .line || tool == .arrow {
            beginLine(at: p, type: tool == .line ? "line" : "arrow",
                      elbow: tool == .arrow && controller.style.elbowArrow)
        } else {
            beginShape(at: p, type: tool.rawValue)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing else { return }
        let p = scenePoint(event)
        switch drag {
        case .pan:
            let v = viewPoint(event)
            camera.pan(byViewDelta: CGSize(width: v.x - lastPanPoint.x, height: v.y - lastPanPoint.y))
            lastPanPoint = v
            needsDisplay = true
        case .create(let id):
            scene.update(id: id) { e in
                e.width = p.x - dragStart.x
                e.height = p.y - dragStart.y
            }
        case .line(let id):
            scene.update(id: id) { e in
                e.points = [[0, 0], [p.x - e.x, p.y - e.y]]
            }
        case .freedraw(let id):
            scene.update(id: id) { e in
                e.points?.append([p.x - e.x, p.y - e.y])
            }
        case .move(let origins):
            let dx = p.x - dragStart.x, dy = p.y - dragStart.y
            for (id, origin) in origins {
                scene.update(id: id) { e in e.x = origin.x + dx; e.y = origin.y + dy }
            }
            rebuildArrowsBound(to: Set(origins.keys))
        case .resize(let id, let handle, let start):
            resize(id: id, handle: handle, start: start, to: p)
            rebuildArrowsBound(to: [id])
        case .endpoint(let id, let isStart, let otherAbs):
            let a = isStart ? p : otherAbs
            let b = isStart ? otherAbs : p
            scene.update(id: id) { e in
                e.x = a.x; e.y = a.y
                e.points = [[0, 0], [b.x - a.x, b.y - a.y]]
            }
            renderer.invalidate(id)
        case .marquee(let startScene):
            marqueeRect = CGRect(x: min(startScene.x, p.x), y: min(startScene.y, p.y),
                                 width: abs(p.x - startScene.x), height: abs(p.y - startScene.y))
            needsDisplay = true
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isEditing else { return }
        switch drag {
        case .create(let id):
            finalizeCreatedShape(id)
        case .marquee:
            if let m = marqueeRect {
                scene.selection = Set(scene.elements(in: m).map(\.id))
            }
            marqueeRect = nil
            updateSelectionState()
            needsDisplay = true
        case .line(let id):
            finalizeLine(id)
        case .endpoint(let id, let isStart, _):
            // Re-bind the dragged end if it now sits on a shape, then re-route.
            if let arrow = scene.element(id) {
                let pt = isStart ? arrow.absolutePoints.first : arrow.absolutePoints.last
                let shape = pt.flatMap { topShape(at: $0, excluding: id, tolerance: 20) }
                scene.update(id: id) { e in
                    if isStart { e.startBindingId = shape?.id } else { e.endBindingId = shape?.id }
                }
                rebuildArrow(id)
            }
        case .freedraw:
            break
        default:
            break
        }
        drag = .none
    }

    // MARK: Interactions

    private func beginSelectInteraction(at p: CGPoint, viewPt: CGPoint, shift: Bool) {
        // Single line/arrow: grab an endpoint handle to adjust it.
        if scene.selection.count == 1, let id = scene.selection.first,
           let e = scene.element(id), e.type == "line" || e.type == "arrow",
           let first = e.absolutePoints.first, let last = e.absolutePoints.last {
            let firstV = camera.sceneToView(first), lastV = camera.sceneToView(last)
            if hypot(viewPt.x - firstV.x, viewPt.y - firstV.y) <= 9 {
                scene.beginEdit(); drag = .endpoint(id: id, isStart: true, otherAbs: last); return
            }
            if hypot(viewPt.x - lastV.x, viewPt.y - lastV.y) <= 9 {
                scene.beginEdit(); drag = .endpoint(id: id, isStart: false, otherAbs: first); return
            }
        }
        // Resize handle hit (single selection, box-shaped elements).
        if scene.selection.count == 1, let sb = selectionBounds(),
           let e = scene.element(scene.selection.first!), e.type != "line", e.type != "arrow" {
            let r = viewRect(sb).insetBy(dx: -4, dy: -4)
            for h in Handle.allCases where handleRect(h, in: r).insetBy(dx: -3, dy: -3).contains(viewPt) {
                if let id = scene.selection.first {
                    scene.beginEdit()
                    drag = .resize(id: id, handle: h, start: e.boundingRect)
                    return
                }
            }
        }
        if let hit = scene.hitTest(p, tolerance: 8 / camera.zoom) {
            if shift {
                if scene.selection.contains(hit.id) { scene.selection.remove(hit.id) }
                else { scene.selection.insert(hit.id) }
            } else if !scene.selection.contains(hit.id) {
                scene.selection = [hit.id]
            }
            updateSelectionState()
            scene.beginEdit()
            let origins = Dictionary(uniqueKeysWithValues:
                scene.elements.filter { scene.selection.contains($0.id) }.map { ($0.id, CGPoint(x: $0.x, y: $0.y)) })
            drag = .move(origins: origins)
        } else {
            if !shift { scene.selection.removeAll() }
            updateSelectionState()
            drag = .marquee(startScene: p)
        }
        needsDisplay = true
    }

    private func beginShape(at p: CGPoint, type: String) {
        scene.beginEdit()
        var e = makeElement(type: type, x: p.x, y: p.y, width: 0, height: 0)
        if type == "rectangle" || type == "diamond" {
            e.roundness = controller.style.rounded ? Element.Roundness(type: 3) : nil
        }
        scene.add(e)
        drag = .create(id: e.id)
    }

    private func beginLine(at p: CGPoint, type: String, elbow: Bool = false) {
        scene.beginEdit()
        var e = makeElement(type: type, x: p.x, y: p.y, width: 0, height: 0)
        e.points = [[0, 0], [0, 0]]
        e.backgroundColor = "transparent"
        e.elbowed = elbow
        if type == "arrow" {
            let s = controller.style
            e.startArrowhead = s.startArrowhead == "none" ? nil : s.startArrowhead
            e.endArrowhead = s.endArrowhead == "none" ? nil : s.endArrowhead
        }
        scene.add(e)
        drag = .line(id: e.id)
    }

    /// On release, bind endpoints to any shapes under them and route the arrow.
    private func finalizeLine(_ id: String) {
        guard let arrow = scene.element(id) else { return }
        let abs = arrow.absolutePoints
        guard let start = abs.first, let end = abs.last else { return }
        if hypot(end.x - start.x, end.y - start.y) < 4 { scene.remove(id: id); return }
        // Generous binding radius so dropping NEAR a shape links it.
        let startShape = topShape(at: start, excluding: id, tolerance: 20)
        let endShape = topShape(at: end, excluding: id, tolerance: 20)
        scene.update(id: id) { el in
            el.startBindingId = startShape?.id
            el.endBindingId = endShape?.id
        }
        rebuildArrow(id)
        scene.selection = [id]
        updateSelectionState()  // stay on the current tool for repeated drawing
    }

    private let connectableTypes: Set<String> = ["rectangle", "ellipse", "diamond", "text", "image"]

    private func topShape(at p: CGPoint, excluding excludeId: String, tolerance: CGFloat = 4) -> Element? {
        for e in scene.elements.reversed()
        where e.id != excludeId && connectableTypes.contains(e.type) && !e.locked {
            if e.hitTest(p, tolerance: tolerance) { return e }
        }
        return nil
    }

    /// Recompute a bound arrow's endpoints (snapped to shape edges) + elbow route.
    private func rebuildArrow(_ id: String) {
        guard let arrow = scene.element(id), arrow.type == "arrow" || arrow.type == "line" else { return }
        let abs = arrow.absolutePoints
        guard var a = abs.first, var b = abs.last else { return }
        let startShape = arrow.startBindingId.flatMap { scene.element($0) }
        let endShape = arrow.endBindingId.flatMap { scene.element($0) }
        let bCenter = endShape.map { CGPoint(x: $0.boundingRect.midX, y: $0.boundingRect.midY) } ?? b
        let aCenter = startShape.map { CGPoint(x: $0.boundingRect.midX, y: $0.boundingRect.midY) } ?? a
        if let s = startShape { a = ArrowBinding.edgePoint(of: s, toward: bCenter) }
        if let e = endShape { b = ArrowBinding.edgePoint(of: e, toward: aCenter) }
        let absPoints = arrow.elbowed ? ArrowBinding.elbowRoute(a, b) : [a, b]
        scene.update(id: id) { el in
            el.x = a.x; el.y = a.y
            el.points = absPoints.map { [Double($0.x - a.x), Double($0.y - a.y)] }
        }
        renderer.invalidate(id)
    }

    /// Re-route any arrow bound to a shape that just moved (but not arrows that
    /// are themselves being dragged).
    private func rebuildArrowsBound(to movedIds: Set<String>) {
        for e in scene.elements
        where (e.type == "arrow" || e.type == "line") && !movedIds.contains(e.id) {
            if let s = e.startBindingId, movedIds.contains(s) { rebuildArrow(e.id); continue }
            if let en = e.endBindingId, movedIds.contains(en) { rebuildArrow(e.id) }
        }
    }

    private func beginFreedraw(at p: CGPoint) {
        scene.beginEdit()
        var e = makeElement(type: "freedraw", x: p.x, y: p.y, width: 0, height: 0)
        e.points = [[0, 0]]
        e.backgroundColor = "transparent"
        scene.add(e)
        drag = .freedraw(id: e.id)
    }

    private func finalizeCreatedShape(_ id: String) {
        guard let e = scene.element(id) else { return }
        // A click without a real drag creates nothing — otherwise the first
        // click of a double-click (to add text) would drop a stray shape.
        if abs(e.width) < 4 && abs(e.height) < 4 {
            scene.remove(id: id)
            return
        }
        // Normalize negative sizes into origin+positive extent.
        scene.update(id: id) { el in
            if el.width < 0 { el.x += el.width; el.width = -el.width }
            if el.height < 0 { el.y += el.height; el.height = -el.height }
        }
        scene.selection = [id]
        updateSelectionState()  // stay on the current tool for repeated drawing
    }

    private func resize(id: String, handle: Handle, start: CGRect, to p: CGPoint) {
        var r = start
        if handle.movesLeft { let nx = min(p.x, r.maxX - 4); r.size.width = r.maxX - nx; r.origin.x = nx }
        if handle.movesRight { r.size.width = max(4, p.x - r.minX) }
        if handle.movesTop { let ny = min(p.y, r.maxY - 4); r.size.height = r.maxY - ny; r.origin.y = ny }
        if handle.movesBottom { r.size.height = max(4, p.y - r.minY) }

        guard let element = scene.element(id) else { return }
        switch element.type {
        case "text":
            // Resize the BOX only — keep the font size. The renderer shrinks the
            // text to fit if the box becomes too small (it never scales up).
            scene.update(id: id) { e in
                e.x = r.minX; e.y = r.minY; e.width = r.width; e.height = r.height
            }
        case "freedraw":
            // Remap every point from the old bounding box to the new one.
            let sx = start.width > 0.5 ? r.width / start.width : 1
            let sy = start.height > 0.5 ? r.height / start.height : 1
            let pts = element.absolutePoints.map { pt in
                CGPoint(x: r.minX + (pt.x - start.minX) * sx,
                        y: r.minY + (pt.y - start.minY) * sy)
            }
            guard let origin = pts.first else { return }
            scene.update(id: id) { e in
                e.x = origin.x; e.y = origin.y
                e.points = pts.map { [Double($0.x - origin.x), Double($0.y - origin.y)] }
            }
        default:
            scene.update(id: id) { e in
                e.x = r.minX; e.y = r.minY; e.width = r.width; e.height = r.height
            }
        }
        renderer.invalidate(id)
    }

    /// Clear everything on the current board (confirmed, undoable with ⌘Z).
    func clearBoard() {
        guard !scene.elements.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Clear this board?"
        alert.informativeText = "Removes everything on the current board. You can undo with ⌘Z."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        commitText()
        scene.beginEdit()
        renderer.invalidateAll()
        scene.removeAllElements()
        updateSelectionState()
    }

    /// Called after switching boards: drop cached paths and clear selection UI.
    func boardDidChange() {
        renderer.invalidateAll()
        commitText()
        updateSelectionState()
        needsDisplay = true
    }

    /// Drop a linked file node at the center of the current view.
    func addFileNode(path: String) {
        addLink(link: path, name: (path as NSString).lastPathComponent)
    }

    /// Drop a link node (file/folder/URL) at a scene point (default view center).
    func addLink(link: String, name: String, at point: CGPoint? = nil) {
        let size = 16.0
        let isURL = link.contains("://")
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: (link as NSString).expandingTildeInPath, isDirectory: &isDir)
        let icon = isURL ? "🔗 " : (isDir.boolValue ? "📁 " : "📄 ")
        let display = icon + name
        let width = (display as NSString).size(withAttributes: [.font: Fonts.handDrawn(size: CGFloat(size))]).width
        let center = point ?? camera.viewToScene(CGPoint(x: bounds.midX, y: bounds.midY))
        scene.beginEdit()
        var e = makeElement(type: "file", x: center.x - Double(width) / 2, y: center.y - size / 2,
                            width: Double(width) + 6, height: size * 1.3)
        e.text = name
        e.link = link
        e.backgroundColor = "transparent"
        e.fontSize = size
        scene.add(e)
        scene.selection = [e.id]
        updateSelectionState()
    }

    private func openLink(_ link: String) {
        let url: URL? = link.contains("://")
            ? URL(string: link)
            : URL(fileURLWithPath: (link as NSString).expandingTildeInPath)
        if let url { NSWorkspace.shared.open(url) }
    }

    private func makeElement(type: String, x: Double, y: Double, width: Double, height: Double) -> Element {
        let s = controller.style
        return Element(
            type: type, x: x, y: y, width: width, height: height,
            strokeColor: s.strokeColor, backgroundColor: s.backgroundColor,
            fillStyle: s.fillStyle, strokeWidth: s.strokeWidth, strokeStyle: s.strokeStyle,
            roughness: s.roughness, opacity: s.opacity,
            updated: Date().timeIntervalSince1970 * 1000
        )
    }

    // MARK: Selection / style

    private func updateSelectionState() {
        controller.hasSelection = !scene.selection.isEmpty
        controller.selectionType = scene.selection.first.flatMap { scene.element($0)?.type }
        // Reflect the (first) selected element's style into the inspector.
        if let id = scene.selection.first, let e = scene.element(id) {
            controller.style.strokeColor = e.strokeColor
            controller.style.backgroundColor = e.backgroundColor
            controller.style.fillStyle = e.fillStyle
            controller.style.strokeWidth = e.strokeWidth
            controller.style.strokeStyle = e.strokeStyle
            controller.style.roughness = e.roughness
            controller.style.opacity = e.opacity
            if let fs = e.fontSize { controller.style.fontSize = fs }
            if let ff = e.fontFamily { controller.style.fontFamily = ff }
            controller.style.rounded = e.roundness != nil
            controller.style.elbowArrow = e.elbowed
            controller.style.startArrowhead = e.startArrowhead ?? "none"
            controller.style.endArrowhead = e.endArrowhead ?? "none"
        }
    }

    private func applyStyleToSelection() {
        guard !scene.selection.isEmpty else { return }
        scene.beginEdit()
        let s = controller.style
        for id in scene.selection {
            scene.update(id: id) { e in
                e.strokeColor = s.strokeColor
                e.backgroundColor = s.backgroundColor
                e.fillStyle = s.fillStyle
                e.strokeWidth = s.strokeWidth
                e.strokeStyle = s.strokeStyle
                e.roughness = s.roughness
                e.opacity = s.opacity
                if e.type == "rectangle" || e.type == "diamond" {
                    e.roundness = s.rounded ? Element.Roundness(type: 3) : nil
                }
                if e.type == "arrow" {
                    e.elbowed = s.elbowArrow
                    e.startArrowhead = s.startArrowhead == "none" ? nil : s.startArrowhead
                    e.endArrowhead = s.endArrowhead == "none" ? nil : s.endArrowhead
                }
                if e.type == "text" {
                    e.fontSize = s.fontSize
                    e.fontFamily = s.fontFamily
                    let font = Fonts.font(family: s.fontFamily, size: CGFloat(s.fontSize))
                    let w = ((e.text ?? "") as NSString).size(withAttributes: [.font: font]).width
                    e.width = Double(w) + 8
                    e.height = s.fontSize * 1.25
                }
            }
            renderer.invalidate(id)
            if let el = scene.element(id), el.type == "arrow" || el.type == "line" { rebuildArrow(id) }
        }
        // If a text element is being edited live, reflect color/size in the field.
        if let id = editingTextId, scene.selection.contains(id), let field = textField {
            field.font = Fonts.handDrawn(size: CGFloat(s.fontSize) * camera.zoom)
            field.textColor = NSColor.excalidraw(s.strokeColor)
            field.frame.size.height = CGFloat(s.fontSize) * camera.zoom + 8
        }
    }

    private func deleteSelectionAction() {
        guard !scene.selection.isEmpty else { return }
        scene.beginEdit()
        scene.selection.forEach { renderer.invalidate($0) }
        scene.removeSelected()
        updateSelectionState()
    }

    // MARK: Clipboard

    /// Copy selected elements to the in-app clipboard; also put any text on the
    /// system pasteboard so it can be pasted into other apps.
    private func copySelection() {
        let sel = scene.elements.filter { scene.selection.contains($0.id) }
        guard !sel.isEmpty else { return }
        clipboard = sel
        let texts = sel.compactMap(\.text).filter { !$0.isEmpty }
        if !texts.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(texts.joined(separator: "\n"), forType: .string)
        }
    }

    /// Paste in-app elements (offset), or system-clipboard text as a text box.
    private func paste() {
        scene.beginEdit()
        if !clipboard.isEmpty {
            var newIds: [String] = []
            for var e in clipboard {
                e.id = UUID().uuidString
                e.x += 20; e.y += 20
                e.version = 1
                e.startBindingId = nil; e.endBindingId = nil // copies aren't linked
                scene.add(e)
                newIds.append(e.id)
            }
            // Offset the buffer so repeated pastes cascade.
            clipboard = clipboard.map { var c = $0; c.x += 20; c.y += 20; return c }
            scene.selection = Set(newIds)
        } else if let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
            let center = camera.viewToScene(CGPoint(x: bounds.midX, y: bounds.midY))
            let size = controller.style.fontSize
            let font = Fonts.handDrawn(size: CGFloat(size))
            let lines = str.components(separatedBy: "\n")
            let width = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 80
            var e = makeElement(type: "text", x: center.x, y: center.y, width: 0, height: 0)
            e.text = str
            e.fontSize = size
            e.fontFamily = 5
            e.strokeColor = controller.style.strokeColor
            e.width = Double(width) + 8
            e.height = size * 1.25 * Double(lines.count)
            scene.add(e)
            scene.selection = [e.id]
        }
        updateSelectionState()
    }

    // MARK: Keyboard

    // Cmd-shortcuts arrive here (not keyDown). Without an app menu they'd
    // otherwise be dropped. Returning true marks them handled.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isEditing, event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = event.modifierFlags.contains(.shift)
        switch event.charactersIgnoringModifiers {
        case "z": shift ? scene.redo() : scene.undo()
                  renderer.invalidateAll(); updateSelectionState(); return true
        case "c": copySelection(); return true
        case "x": copySelection(); deleteSelectionAction(); return true
        case "v": paste(); return true
        case "a": scene.selection = Set(scene.elements.map(\.id))
                  updateSelectionState(); needsDisplay = true; return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isEditing else { return super.keyDown(with: event) }
        if event.keyCode == 49 { spaceDown = true; return } // space
        if event.charactersIgnoringModifiers == "/" { onSlashSearch?(); return }

        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        if cmd, let ch = event.charactersIgnoringModifiers {
            switch ch {
            case "z": shift ? scene.redo() : scene.undo()
                      renderer.invalidateAll(); updateSelectionState(); return
            case "c": copySelection(); return
            case "x": copySelection(); deleteSelectionAction(); return
            case "v": paste(); return
            case "a": scene.selection = Set(scene.elements.map(\.id)); updateSelectionState(); needsDisplay = true; return
            default: break
            }
        }
        switch event.keyCode {
        case 51, 117: deleteSelectionAction(); return // delete / fwd-delete
        case 53: scene.selection.removeAll(); updateSelectionState(); needsDisplay = true; return // esc
        default: break
        }
        if let ch = event.charactersIgnoringModifiers?.first,
           let tool = Tool.allCases.first(where: { $0.key == ch }) {
            controller.tool = tool
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceDown = false }
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEditing else { return }
        if event.modifierFlags.contains(.command) {
            let factor = 1 - event.scrollingDeltaY * 0.01
            camera.zoom(by: factor, around: viewPoint(event))
        } else {
            camera.pan(byViewDelta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
        }
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        guard isEditing else { return }
        camera.zoom(by: 1 + event.magnification, around: viewPoint(event))
        needsDisplay = true
    }

    // MARK: Text editing

    private func beginText(at p: CGPoint) {
        scene.beginEdit()
        var e = makeElement(type: "text", x: p.x, y: p.y, width: 0, height: 0)
        e.text = ""
        e.fontSize = controller.style.fontSize
        e.fontFamily = controller.style.fontFamily
        e.strokeColor = controller.style.strokeColor
        scene.add(e)
        scene.selection = [e.id]
        presentTextEditor(for: e)
    }

    /// Edit an existing text element in place (double-click).
    private func beginEditingText(_ e: Element) {
        scene.beginEdit()
        scene.selection = [e.id]
        updateSelectionState()
        presentTextEditor(for: e)
    }

    private func presentTextEditor(for e: Element) {
        let viewOrigin = camera.sceneToView(CGPoint(x: e.x, y: e.y))
        let size = CGFloat(e.fontSize ?? 20) * camera.zoom
        let field = NSTextField(frame: NSRect(x: viewOrigin.x, y: viewOrigin.y,
                                              width: max(240, e.width * camera.zoom + 40), height: size + 8))
        field.stringValue = e.text ?? ""
        field.font = Fonts.font(family: e.fontFamily ?? 1, size: size)
        field.isBordered = false
        // Match the board backdrop so the editor blends (transparent/wash/white).
        field.drawsBackground = editBoardOpacity > 0.02
        field.backgroundColor = NSColor.white.withAlphaComponent(editBoardOpacity)
        field.textColor = NSColor.excalidraw(e.strokeColor)
        field.focusRingType = .none
        field.target = self
        field.action = #selector(textCommitted)
        addSubview(field)
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: (e.text ?? "").count, length: 0)
        textField = field
        editingTextId = e.id
    }

    @objc private func textCommitted() { commitText() }

    private func commitText() {
        guard let field = textField, let id = editingTextId else { return }
        let value = field.stringValue
        let size = CGFloat(scene.element(id)?.fontSize ?? 20)
        let family = scene.element(id)?.fontFamily ?? 1
        if value.isEmpty {
            scene.remove(id: id)
        } else {
            let width = (value as NSString).size(withAttributes: [.font: Fonts.font(family: family, size: size)]).width
            scene.update(id: id) { e in
                e.text = value
                e.width = Double(width) + 8
                e.height = Double(size) * 1.25
            }
            renderer.invalidate(id)
        }
        field.removeFromSuperview()
        textField = nil
        editingTextId = nil
        controller.tool = .select
        needsDisplay = true
    }
}
