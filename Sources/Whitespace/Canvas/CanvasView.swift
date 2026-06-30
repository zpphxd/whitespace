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

    init(frame: NSRect, scene: Scene, controller: CanvasController) {
        self.scene = scene
        self.controller = controller
        super.init(frame: frame)
        scene.onChange = { [weak self] in
            self?.needsDisplay = true
            self?.onSceneChange?()
        }
        wireController()
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
            beginLine(at: p, type: tool == .arrow ? "arrow" : "line")
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
        case .resize(let id, let handle, let start):
            resize(id: id, handle: handle, start: start, to: p)
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
        case .freedraw, .line:
            // Auto-revert to select after a one-shot draw, like Excalidraw's lock-off.
            break
        default:
            break
        }
        drag = .none
    }

    // MARK: Interactions

    private func beginSelectInteraction(at p: CGPoint, viewPt: CGPoint, shift: Bool) {
        // Resize handle hit (single selection).
        if scene.selection.count == 1, let sb = selectionBounds() {
            let r = viewRect(sb).insetBy(dx: -4, dy: -4)
            for h in Handle.allCases where handleRect(h, in: r).insetBy(dx: -3, dy: -3).contains(viewPt) {
                if let id = scene.selection.first, let e = scene.element(id) {
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
        let e = makeElement(type: type, x: p.x, y: p.y, width: 0, height: 0)
        scene.add(e)
        drag = .create(id: e.id)
    }

    private func beginLine(at p: CGPoint, type: String) {
        scene.beginEdit()
        var e = makeElement(type: type, x: p.x, y: p.y, width: 0, height: 0)
        e.points = [[0, 0], [0, 0]]
        e.backgroundColor = "transparent"
        if type == "arrow" { e.endArrowhead = "arrow" }
        scene.add(e)
        drag = .line(id: e.id)
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
        // Tiny drag → give a sensible default size and keep it selected.
        if abs(e.width) < 4 && abs(e.height) < 4 {
            scene.update(id: id) { el in el.width = 120; el.height = 80 }
        } else {
            // Normalize negative sizes into origin+positive extent.
            scene.update(id: id) { el in
                if el.width < 0 { el.x += el.width; el.width = -el.width }
                if el.height < 0 { el.y += el.height; el.height = -el.height }
            }
        }
        scene.selection = [id]
        controller.tool = .select
        updateSelectionState()
    }

    private func resize(id: String, handle: Handle, start: CGRect, to p: CGPoint) {
        var r = start
        if handle.movesLeft { let nx = min(p.x, r.maxX - 4); r.size.width = r.maxX - nx; r.origin.x = nx }
        if handle.movesRight { r.size.width = max(4, p.x - r.minX) }
        if handle.movesTop { let ny = min(p.y, r.maxY - 4); r.size.height = r.maxY - ny; r.origin.y = ny }
        if handle.movesBottom { r.size.height = max(4, p.y - r.minY) }
        scene.update(id: id) { e in
            e.x = r.minX; e.y = r.minY; e.width = r.width; e.height = r.height
        }
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
                if e.type == "text" {
                    e.fontSize = s.fontSize
                    let font = Fonts.handDrawn(size: CGFloat(s.fontSize))
                    let w = ((e.text ?? "") as NSString).size(withAttributes: [.font: font]).width
                    e.width = Double(w) + 8
                    e.height = s.fontSize * 1.25
                }
            }
            renderer.invalidate(id)
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

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard isEditing else { return super.keyDown(with: event) }
        if event.keyCode == 49 { spaceDown = true; return } // space

        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        if cmd, event.charactersIgnoringModifiers == "z" {
            shift ? scene.redo() : scene.undo()
            renderer.invalidateAll(); updateSelectionState(); return
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
        e.fontFamily = 5
        e.strokeColor = controller.style.strokeColor
        scene.add(e)
        scene.selection = [e.id]
        presentTextEditor(for: e)
    }

    private func presentTextEditor(for e: Element) {
        let viewOrigin = camera.sceneToView(CGPoint(x: e.x, y: e.y))
        let size = CGFloat(e.fontSize ?? 20) * camera.zoom
        let field = NSTextField(frame: NSRect(x: viewOrigin.x, y: viewOrigin.y, width: 240, height: size + 8))
        field.font = Fonts.handDrawn(size: size)
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.white.withAlphaComponent(0.9)
        field.textColor = NSColor.excalidraw(e.strokeColor)
        field.focusRingType = .none
        field.target = self
        field.action = #selector(textCommitted)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        editingTextId = e.id
    }

    @objc private func textCommitted() { commitText() }

    private func commitText() {
        guard let field = textField, let id = editingTextId else { return }
        let value = field.stringValue
        let size = CGFloat(scene.element(id)?.fontSize ?? 20)
        if value.isEmpty {
            scene.remove(id: id)
        } else {
            let width = (value as NSString).size(withAttributes: [.font: Fonts.handDrawn(size: size)]).width
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
