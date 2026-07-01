import AppKit
import Combine
import Quartz

/// The drawing surface: renders the scene under the camera and handles all
/// pointer/keyboard interaction (create, select, move, resize, pan, zoom).
final class CanvasView: NSView {
    private var cancellables = Set<AnyCancellable>()

    let scene: Scene
    let controller: CanvasController
    private let renderer = ElementRenderer()
    private var camera = Camera()

    var isEditing = false {
        didSet {
            needsDisplay = true
            if !isEditing { commitText(); commitCellEdit() }
            updatePipeAnimation()
        }
    }

    /// Called after any scene mutation so the app can schedule an autosave.
    var onSceneChange: (() -> Void)?

    /// Called when "/" is pressed — opens the file-link search palette.
    var onSlashSearch: (() -> Void)?

    /// Called when a `.excalidraw` file is dropped/opened — load it as a board.
    var onOpenFile: ((URL) -> Void)?

    /// Whiteboard backdrop opacity. Idle is *always* transparent — drawings float
    /// on the wallpaper — so leaving edit mode is a clean on/off flip. Only the
    /// edit-mode backdrop is configurable (light wash / solid / transparent).
    var idleBoardOpacity: CGFloat = 0
    var editBoardOpacity: CGFloat = Settings.editBoardOpacity

    // Interaction state
    private enum Drag {
        case none
        case create(id: String)
        case line(id: String)
        case freedraw(id: String)
        case move(origins: [String: CGPoint])
        case resize(id: String, handle: Handle, start: CGRect)
        case vertex(id: String, index: Int)
        case marquee(startScene: CGPoint)
        case pan
        case erase
        case rotate(id: String, center: CGPoint, offset: CGFloat)
        case lasso
        case laser
    }
    private var drag: Drag = .none
    private var dragStart: CGPoint = .zero
    private var lastPanPoint: CGPoint = .zero
    private var spaceDown = false
    private var marqueeRect: CGRect?
    /// The line/arrow currently being built by click-to-add-point placement (nil
    /// when not in multi-point mode). Its last point tracks the cursor as a preview.
    private var multiPointLineId: String?
    private var lassoPoints: [CGPoint] = []
    private var laserPoints: [CGPoint] = []
    private var laserFadeTimer: Timer?

    private var textField: NSTextField?
    private var editingTextId: String?
    private var cellScroll: NSScrollView?
    private var cellEditor: NSTextView?
    private var editingCellId: String?
    private var runningCells: Set<String> = []
    private var pipeTimer: Timer?
    private var pipePulses: [String: Double] = [:]
    private var graphOrder: [String] = []
    private var graphOutputs: [String: String] = [:]
    private var clipboard: [Element] = []
    private let chartWheel = ChartWheelWindow()

    init(frame: NSRect, scene: Scene, controller: CanvasController) {
        self.scene = scene
        self.controller = controller
        super.init(frame: frame)
        scene.onChange = { [weak self] in
            self?.needsDisplay = true
            self?.onSceneChange?()
            self?.updatePipeAnimation()
        }
        registerForDraggedTypes([.fileURL])
        wireController()

        // Redraw when a background QuickLook thumbnail becomes available.
        NotificationCenter.default.addObserver(self, selector: #selector(thumbnailReady),
                                               name: ThumbnailCache.readyNotification, object: nil)

        // Switching to a non-select tool deselects, so the inspector reflects
        // the new tool (e.g. the text tool shows Font / Text size).
        controller.$tool
            .sink { [weak self] newTool in
                guard let self else { return }
                if self.multiPointLineId != nil { self.finishMultiPointLine() }
                guard newTool != .select, !self.scene.selection.isEmpty else { return }
                self.commitText()
                self.scene.selection.removeAll()
                self.controller.hasSelection = false
                self.controller.selectionType = nil
                self.needsDisplay = true
            }
            .store(in: &cancellables)
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
            let ext = url.pathExtension.lowercased()
            if ext == "excalidraw" {
                onOpenFile?(url)
            } else if Self.imageExtensions.contains(ext) {
                addImage(path: url.path, at: p)
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
        controller.alignAction = { [weak self] mode in self?.align(mode) }
    }

    /// Align or distribute the selected elements (≥2).
    private func align(_ mode: String) {
        let ids = scene.selection
        guard ids.count >= 2 else { return }
        let boxes = scene.elements.filter { ids.contains($0.id) }.map { ($0.id, $0.boundingRect) }
        let union = boxes.dropFirst().reduce(boxes[0].1) { $0.union($1.1) }
        scene.beginEdit()
        func move(_ id: String, dx: CGFloat = 0, dy: CGFloat = 0) {
            scene.update(id: id) { $0.x += dx; $0.y += dy }
        }
        switch mode {
        case "left": boxes.forEach { move($0.0, dx: union.minX - $0.1.minX) }
        case "centerH": boxes.forEach { move($0.0, dx: union.midX - $0.1.midX) }
        case "right": boxes.forEach { move($0.0, dx: union.maxX - $0.1.maxX) }
        case "top": boxes.forEach { move($0.0, dy: union.minY - $0.1.minY) }
        case "middleV": boxes.forEach { move($0.0, dy: union.midY - $0.1.midY) }
        case "bottom": boxes.forEach { move($0.0, dy: union.maxY - $0.1.maxY) }
        case "distH":
            let sorted = boxes.sorted { $0.1.midX < $1.1.midX }
            let lo = sorted.first!.1.midX, hi = sorted.last!.1.midX
            let step = (hi - lo) / CGFloat(sorted.count - 1)
            for (i, b) in sorted.enumerated() { move(b.0, dx: lo + CGFloat(i) * step - b.1.midX) }
        case "distV":
            let sorted = boxes.sorted { $0.1.midY < $1.1.midY }
            let lo = sorted.first!.1.midY, hi = sorted.last!.1.midY
            let step = (hi - lo) / CGFloat(sorted.count - 1)
            for (i, b) in sorted.enumerated() { move(b.0, dy: lo + CGFloat(i) * step - b.1.midY) }
        default: break
        }
        rebuildArrowsBound(to: ids)
        syncBoundTexts(to: ids)
        updateSelectionState()
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
        drawLasso(in: ctx)
        drawLaser(in: ctx)
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

        // Single line/arrow: show draggable point handles (and midpoint "ghost"
        // handles that insert a new bend when dragged) instead of a box.
        if scene.selection.count == 1,
           let e = scene.element(scene.selection.first!),
           e.type == "line" || e.type == "arrow" {
            let purple = NSColor(hex: 0x6965db)
            let pts = e.absolutePoints
            ctx.setLineWidth(1.5)
            // Midpoint ghosts first (drawn under the solid vertex handles).
            // Elbow arrows auto-route, so they don't take manual bends.
            if !e.elbowed && pts.count >= 2 {
                for i in 0..<(pts.count - 1) {
                    let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2,
                                      y: (pts[i].y + pts[i + 1].y) / 2)
                    let v = camera.sceneToView(mid)
                    let hr = CGRect(x: v.x - 4, y: v.y - 4, width: 8, height: 8)
                    ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
                    ctx.fillEllipse(in: hr)
                    ctx.setStrokeColor(purple.withAlphaComponent(0.5).cgColor)
                    ctx.strokeEllipse(in: hr)
                }
            }
            // Real vertices (solid handles).
            ctx.setStrokeColor(purple.cgColor)
            for pt in pts {
                let v = camera.sceneToView(pt)
                let hr = CGRect(x: v.x - 5, y: v.y - 5, width: 10, height: 10)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: hr)
                ctx.strokeEllipse(in: hr)
            }
            return
        }

        let purple = NSColor(hex: 0x6965db).cgColor
        ctx.setStrokeColor(purple)
        ctx.setLineWidth(1.5)

        // Single non-linear element: rotated outline + rotation handle.
        if scene.selection.count == 1, let e = scene.element(scene.selection.first!) {
            let rect = e.boundingRect
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let a = CGFloat(e.angle)
            let cornersV = [
                CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
            ].map { camera.sceneToView(rotatePoint($0, around: c, by: a)) }
            ctx.move(to: cornersV[0])
            for i in 1..<4 { ctx.addLine(to: cornersV[i]) }
            ctx.closePath(); ctx.strokePath()

            // Resize handles only when unrotated (axis-aligned).
            if abs(e.angle) < 0.0001 {
                let r = viewRect(rect).insetBy(dx: -4, dy: -4)
                for h in Handle.allCases {
                    let hr = handleRect(h, in: r)
                    ctx.setFillColor(NSColor.white.cgColor); ctx.fill(hr)
                    ctx.setStrokeColor(purple); ctx.stroke(hr)
                }
            }
            // Rotation handle above the top edge.
            let topMid = camera.sceneToView(rotatePoint(CGPoint(x: rect.midX, y: rect.minY), around: c, by: a))
            let knob = rotationKnobView(for: e)
            ctx.setStrokeColor(purple)
            ctx.move(to: topMid); ctx.addLine(to: knob); ctx.strokePath()
            let kr = CGRect(x: knob.x - 5, y: knob.y - 5, width: 10, height: 10)
            ctx.setFillColor(NSColor.white.cgColor); ctx.fillEllipse(in: kr)
            ctx.setStrokeColor(purple); ctx.strokeEllipse(in: kr)
            return
        }

        // Multi-selection: axis-aligned box.
        let r = viewRect(bounds).insetBy(dx: -4, dy: -4)
        ctx.stroke(r)
    }

    private func rotatePoint(_ p: CGPoint, around c: CGPoint, by angle: CGFloat) -> CGPoint {
        let s = sin(angle), co = cos(angle)
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * co - dy * s, y: c.y + dx * s + dy * co)
    }

    /// View-space position of an element's rotation knob.
    private func rotationKnobView(for e: Element) -> CGPoint {
        let rect = e.boundingRect
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let above = CGPoint(x: rect.midX, y: rect.minY - 26 / camera.zoom)
        return camera.sceneToView(rotatePoint(above, around: c, by: CGFloat(e.angle)))
    }

    private func drawLasso(in ctx: CGContext) {
        guard lassoPoints.count > 1 else { return }
        let pts = lassoPoints.map { camera.sceneToView($0) }
        ctx.setStrokeColor(NSColor(hex: 0x6965db).cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [5, 4])
        ctx.move(to: pts[0]); pts.dropFirst().forEach { ctx.addLine(to: $0) }
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private func drawLaser(in ctx: CGContext) {
        guard laserPoints.count > 1 else { return }
        let pts = laserPoints.map { camera.sceneToView($0) }
        let n = pts.count
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        // Taper alpha and width from the tail (faint, thin) to the head (bright, thick).
        for i in 1..<n {
            let t = CGFloat(i) / CGFloat(n - 1)
            ctx.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.12 + 0.88 * t).cgColor)
            ctx.setLineWidth(1.5 + 4 * t)
            ctx.move(to: pts[i - 1]); ctx.addLine(to: pts[i])
            ctx.strokePath()
        }
        let head = pts[n - 1]
        ctx.setFillColor(NSColor.systemRed.cgColor)
        ctx.fillEllipse(in: CGRect(x: head.x - 4, y: head.y - 4, width: 8, height: 8))
    }

    /// Hold the full trail briefly, then retract it from the tail toward the head.
    private func startLaserFade() {
        laserFadeTimer?.invalidate()
        laserFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.retractLaser() }
        }
    }

    private func retractLaser() {
        laserFadeTimer?.invalidate()
        laserFadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.laserPoints.count > 1 {
                    let step = max(1, self.laserPoints.count / 30)   // ~0.5s sweep
                    self.laserPoints.removeFirst(min(step, self.laserPoints.count - 1))
                    self.needsDisplay = true
                } else {
                    self.laserPoints = []
                    self.needsDisplay = true
                    self.laserFadeTimer?.invalidate()
                    self.laserFadeTimer = nil
                }
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
        commitCellEdit()
        let p = scenePoint(event)

        // Placing points on a multi-point line: each click commits a vertex.
        if multiPointLineId != nil, controller.tool == .line || controller.tool == .arrow {
            handleMultiPointClick(at: p, doubleClick: event.clickCount == 2)
            return
        }

        // Double-click: open a linked element, edit a text element, or start a
        // new text box on empty canvas.
        if event.clickCount == 2 {
            if let hit = scene.hitTest(p, tolerance: 8 / camera.zoom) {
                if hit.type == "cell" { beginEditingCell(hit); return }
                if let link = hit.link, !link.isEmpty { openLink(link); return }
                if hit.type == "text" { beginEditingText(hit); return }
                if ["rectangle", "ellipse", "diamond"].contains(hit.type) {
                    beginContainerText(hit); return
                }
            }
            beginText(at: p)
            return
        }

        // Single click on a cell's run glyph (top-right of the header) runs it.
        if controller.tool == .select, let hit = scene.hitTest(p, tolerance: 8 / camera.zoom),
           hit.type == "cell", cellRunHitRect(hit).contains(p) {
            runCell(hit.id); return
        }

        dragStart = p
        lastPanPoint = viewPoint(event)

        if spaceDown { drag = .pan; return }

        let tool = controller.tool
        if tool == .hand {
            drag = .pan
        } else if tool == .eraser {
            scene.beginEdit()
            eraseAt(p)
            drag = .erase
        } else if tool == .select {
            beginSelectInteraction(at: p, viewPt: viewPoint(event), shift: event.modifierFlags.contains(.shift))
        } else if tool == .text {
            beginText(at: p)
        } else if tool == .freedraw {
            beginFreedraw(at: p)
        } else if tool == .line || tool == .arrow {
            beginLine(at: p, type: tool == .line ? "line" : "arrow",
                      elbow: tool == .arrow && controller.style.elbowArrow)
        } else if tool == .lasso {
            lassoPoints = [p]; drag = .lasso
        } else if tool == .laser {
            laserFadeTimer?.invalidate(); laserFadeTimer = nil
            laserPoints = [p]; drag = .laser
        } else {
            beginShape(at: p, type: tool.rawValue)  // rectangle / ellipse / diamond / frame
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
            syncBoundTexts(to: Set(origins.keys))
        case .resize(let id, let handle, let start):
            resize(id: id, handle: handle, start: start, to: p)
            rebuildArrowsBound(to: [id])
            syncBoundTexts(to: [id])
        case .vertex(let id, let index):
            guard var pts = scene.element(id)?.absolutePoints, index < pts.count else { break }
            pts[index] = p
            setAbsolutePoints(id, pts)
            renderer.invalidate(id)
        case .marquee(let startScene):
            marqueeRect = CGRect(x: min(startScene.x, p.x), y: min(startScene.y, p.y),
                                 width: abs(p.x - startScene.x), height: abs(p.y - startScene.y))
            needsDisplay = true
        case .erase:
            eraseAt(p)
        case .rotate(let id, let center, let offset):
            let a = atan2(p.y - center.y, p.x - center.x)
            scene.update(id: id) { $0.angle = Double(a - offset) }
        case .lasso:
            lassoPoints.append(p); needsDisplay = true
        case .laser:
            laserPoints.append(p); needsDisplay = true
        case .none:
            break
        }
    }

    /// Keep container-bound text matching its shape's box as it moves/resizes.
    private func syncBoundTexts(to ids: Set<String>) {
        for t in scene.elements where t.type == "text" && t.containerId != nil && ids.contains(t.containerId!) {
            guard let container = scene.element(t.containerId!) else { continue }
            let r = container.rect
            scene.update(id: t.id) { e in
                e.x = r.minX; e.y = r.minY; e.width = r.width; e.height = r.height
            }
            renderer.invalidate(t.id)
        }
    }

    // MARK: Frames (containers)

    /// Ids of the elements that belong to the given frame.
    private func frameMembers(_ frameId: String) -> Set<String> {
        Set(scene.elements.filter { $0.frameId == frameId }.map(\.id))
    }

    /// Top-most frame whose rect contains the element's center, if any.
    private func enclosingFrame(of e: Element) -> Element? {
        let c = CGPoint(x: e.boundingRect.midX, y: e.boundingRect.midY)
        return scene.elements.reversed().first { $0.type == "frame" && $0.id != e.id && $0.rect.contains(c) }
    }

    /// After a move/create, update each affected element's frame membership
    /// based on whether it now sits inside a frame.
    private func reassignFrameMembership(_ ids: Set<String>) {
        for id in ids {
            guard let e = scene.element(id), e.type != "frame", e.containerId == nil else { continue }
            let newFrame = enclosingFrame(of: e)?.id
            if e.frameId != newFrame { scene.update(id: id) { $0.frameId = newFrame } }
        }
    }

    /// All element ids sharing the hit element's outermost group (or just it).
    private func groupMembers(of e: Element) -> Set<String> {
        guard let gid = e.groupIds.last else { return [e.id] }
        return Set(scene.elements.filter { $0.groupIds.contains(gid) }.map(\.id))
    }

    private func groupSelection() {
        guard scene.selection.count >= 2 else { return }
        scene.beginEdit()
        let gid = UUID().uuidString
        for id in scene.selection { scene.update(id: id) { $0.groupIds.append(gid) } }
        updateSelectionState()
    }

    private func ungroupSelection() {
        guard !scene.selection.isEmpty else { return }
        scene.beginEdit()
        for id in scene.selection {
            scene.update(id: id) { if !$0.groupIds.isEmpty { $0.groupIds.removeLast() } }
        }
        updateSelectionState()
    }

    private func eraseAt(_ p: CGPoint) {
        if let hit = scene.hitTest(p, tolerance: 6 / camera.zoom) {
            renderer.invalidate(hit.id)
            scene.remove(id: hit.id)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isEditing else { return }
        switch drag {
        case .create(let id):
            finalizeCreatedShape(id)
        case .move(let origins):
            reassignFrameMembership(Set(origins.keys))  // dropped into / out of a frame
        case .marquee:
            if let m = marqueeRect {
                scene.selection = Set(scene.elements(in: m).map(\.id))
            }
            marqueeRect = nil
            updateSelectionState()
            needsDisplay = true
        case .line(let id):
            // A press-release that barely moved is a click: begin multi-point
            // placement instead of finishing a (degenerate) one-segment line.
            if let e = scene.element(id), let a = e.absolutePoints.first, let b = e.absolutePoints.last,
               hypot(b.x - a.x, b.y - a.y) < 6 {
                beginMultiPoint(id)
            } else {
                finalizeLine(id)
            }
        case .vertex(let id, let index):
            // Only endpoints re-bind to shapes; interior bends are kept as-is.
            if let arrow = scene.element(id) {
                let count = arrow.absolutePoints.count
                if index == 0 || index == count - 1 {
                    let isStart = index == 0
                    let pt = isStart ? arrow.absolutePoints.first : arrow.absolutePoints.last
                    if let pt { bindEndpoint(id, isStart: isStart, at: pt) }
                    rebuildArrow(id)
                }
            }
        case .lasso:
            selectInLasso()
            lassoPoints = []
            needsDisplay = true
        case .laser:
            startLaserFade()  // trail retracts from tail → head, then clears
            needsDisplay = true
        case .freedraw(let id):
            reassignFrameMembership([id])
            controller.tool = .select   // revert to the pointer after placing
            updateSelectionState()
        default:
            break
        }
        drag = .none
    }

    /// Live preview: while placing a multi-point line, its trailing point tracks
    /// the cursor so the next segment rubber-bands as you move.
    override func mouseMoved(with event: NSEvent) {
        guard isEditing, let id = multiPointLineId, let e = scene.element(id) else { return }
        var pts = e.absolutePoints
        guard !pts.isEmpty else { return }
        pts[pts.count - 1] = scenePoint(event)
        setAbsolutePoints(id, pts)
        renderer.invalidate(id)
        needsDisplay = true
    }

    private func selectInLasso() {
        guard lassoPoints.count >= 3 else { return }
        let poly = lassoPoints
        let ids = scene.elements.filter { e in
            e.containerId == nil && Self.pointInPolygon(CGPoint(x: e.boundingRect.midX, y: e.boundingRect.midY), poly)
        }.map(\.id)
        scene.selection = Set(ids)
        updateSelectionState()
    }

    private static func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            if (poly[i].y > p.y) != (poly[j].y > p.y),
               p.x < (poly[j].x - poly[i].x) * (p.y - poly[i].y) / (poly[j].y - poly[i].y) + poly[i].x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // MARK: Interactions

    private func beginSelectInteraction(at p: CGPoint, viewPt: CGPoint, shift: Bool) {
        // Single non-linear element: grab the rotation knob.
        if scene.selection.count == 1, let id = scene.selection.first,
           let e = scene.element(id), e.type != "line", e.type != "arrow" {
            let knob = rotationKnobView(for: e)
            if hypot(viewPt.x - knob.x, viewPt.y - knob.y) <= 9 {
                scene.beginEdit()
                let c = CGPoint(x: e.boundingRect.midX, y: e.boundingRect.midY)
                drag = .rotate(id: id, center: c, offset: atan2(p.y - c.y, p.x - c.x) - CGFloat(e.angle))
                return
            }
        }
        // Single line/arrow: grab a point handle to adjust it, or a midpoint
        // ghost to insert a new bend and drag it.
        if scene.selection.count == 1, let id = scene.selection.first,
           let e = scene.element(id), e.type == "line" || e.type == "arrow" {
            let pts = e.absolutePoints
            // 1. Existing vertices (elbow arrows expose only their two endpoints).
            for (i, pt) in pts.enumerated() {
                if e.elbowed && i != 0 && i != pts.count - 1 { continue }
                let v = camera.sceneToView(pt)
                if hypot(viewPt.x - v.x, viewPt.y - v.y) <= 9 {
                    scene.beginEdit(); drag = .vertex(id: id, index: i); return
                }
            }
            // 2. Midpoint ghost → insert a new vertex there and drag it.
            if !e.elbowed && pts.count >= 2 {
                for i in 0..<(pts.count - 1) {
                    let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2,
                                      y: (pts[i].y + pts[i + 1].y) / 2)
                    let v = camera.sceneToView(mid)
                    if hypot(viewPt.x - v.x, viewPt.y - v.y) <= 9 {
                        scene.beginEdit()
                        var abs = pts; abs.insert(mid, at: i + 1)
                        setAbsolutePoints(id, abs)
                        renderer.invalidate(id)
                        drag = .vertex(id: id, index: i + 1); return
                    }
                }
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
            let members = groupMembers(of: hit)  // whole group, if grouped
            if shift {
                if scene.selection.isSuperset(of: members) { scene.selection.subtract(members) }
                else { scene.selection.formUnion(members) }
            } else if !scene.selection.contains(hit.id) {
                scene.selection = members
            } else {
                scene.selection.formUnion(members)
            }
            updateSelectionState()
            scene.beginEdit()
            // Moving a frame carries everything inside it.
            var movingIds = scene.selection
            for id in scene.selection where scene.element(id)?.type == "frame" {
                movingIds.formUnion(frameMembers(id))
            }
            let origins = Dictionary(uniqueKeysWithValues:
                scene.elements.filter { movingIds.contains($0.id) }.map { ($0.id, CGPoint(x: $0.x, y: $0.y)) })
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
        } else if type == "frame" {
            e.text = "Frame"
            e.backgroundColor = "transparent"
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
        // Rounded by default so multi-point lines flow as a smooth curve; elbow
        // arrows stay sharp (right angles).
        e.roundness = elbow ? nil : Element.Roundness(type: 2)
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
        bindEndpoint(id, isStart: true, at: start)
        bindEndpoint(id, isStart: false, at: end)
        rebuildArrow(id)
        scene.selection = [id]
        controller.tool = .select   // revert to the pointer after placing
        updateSelectionState()
    }

    private let connectableTypes: Set<String> = ["rectangle", "ellipse", "diamond", "text", "image", "cell"]

    private func topShape(at p: CGPoint, excluding excludeId: String, tolerance: CGFloat = 4) -> Element? {
        for e in scene.elements.reversed()
        where e.id != excludeId && connectableTypes.contains(e.type) && !e.locked {
            if e.hitTest(p, tolerance: tolerance) { return e }
        }
        return nil
    }

    /// Bind one end of an arrow to whatever shape sits under `absPoint`, recording
    /// the welded fixedPoint (or clearing the binding when there's no shape).
    private func bindEndpoint(_ arrowId: String, isStart: Bool, at absPoint: CGPoint) {
        let shape = topShape(at: absPoint, excluding: arrowId, tolerance: 20)
        let fixed = shape.map { ArrowBinding.fixedPoint(of: $0, at: absPoint) }
        scene.update(id: arrowId) { e in
            if isStart {
                e.startBindingId = shape?.id; e.startBindingPoint = fixed
            } else {
                e.endBindingId = shape?.id; e.endBindingPoint = fixed
            }
        }
    }

    /// Set a linear element's points from absolute scene coordinates, keeping the
    /// origin on the first point (points are stored relative to `x,y`).
    private func setAbsolutePoints(_ id: String, _ pts: [CGPoint]) {
        guard let first = pts.first else { return }
        scene.update(id: id) { e in
            e.x = first.x; e.y = first.y
            e.points = pts.map { [Double($0.x - first.x), Double($0.y - first.y)] }
        }
    }

    /// Recompute a bound arrow's endpoints (snapped to shape edges), preserving
    /// any interior bend points. Elbow arrows re-route orthogonally from scratch.
    private func rebuildArrow(_ id: String) {
        guard let arrow = scene.element(id), arrow.type == "arrow" || arrow.type == "line" else { return }
        var pts = arrow.absolutePoints
        guard pts.count >= 2 else { return }
        let startShape = arrow.startBindingId.flatMap { scene.element($0) }
        let endShape = arrow.endBindingId.flatMap { scene.element($0) }
        // Prefer the welded fixedPoint anchor; fall back to the center-ray edge.
        func startAttach(_ s: Element, toward: CGPoint) -> CGPoint {
            arrow.startBindingPoint.map { ArrowBinding.anchorPoint(of: s, fixed: $0) }
                ?? ArrowBinding.edgePoint(of: s, toward: toward)
        }
        func endAttach(_ e: Element, toward: CGPoint) -> CGPoint {
            arrow.endBindingPoint.map { ArrowBinding.anchorPoint(of: e, fixed: $0) }
                ?? ArrowBinding.edgePoint(of: e, toward: toward)
        }

        if arrow.elbowed {
            // Auto-routed: rebuild the whole dogleg between the two shape edges.
            var a = pts.first!, b = pts.last!
            let bCenter = endShape.map { CGPoint(x: $0.boundingRect.midX, y: $0.boundingRect.midY) } ?? b
            let aCenter = startShape.map { CGPoint(x: $0.boundingRect.midX, y: $0.boundingRect.midY) } ?? a
            if let s = startShape { a = startAttach(s, toward: bCenter) }
            if let e = endShape { b = endAttach(e, toward: aCenter) }
            setAbsolutePoints(id, ArrowBinding.elbowRoute(a, b))
        } else {
            // Move only the bound endpoints; aim each at its interior neighbor so
            // the arrow stays anchored to the shape edge while keeping its bends.
            let startTarget = pts.count > 2 ? pts[1]
                : endShape.map { CGPoint(x: $0.boundingRect.midX, y: $0.boundingRect.midY) } ?? pts.last!
            let endTarget = pts.count > 2 ? pts[pts.count - 2]
                : startShape.map { CGPoint(x: $0.boundingRect.midX, y: $0.boundingRect.midY) } ?? pts.first!
            if let s = startShape { pts[0] = startAttach(s, toward: startTarget) }
            if let e = endShape { pts[pts.count - 1] = endAttach(e, toward: endTarget) }
            setAbsolutePoints(id, pts)
        }
        renderer.invalidate(id)
    }

    // MARK: Multi-point line placement (click-to-add-point)

    /// Enter multi-point mode for a freshly-clicked line/arrow: its last point
    /// becomes a preview that follows the cursor until the next click.
    private func beginMultiPoint(_ id: String) {
        guard let e = scene.element(id), let start = e.absolutePoints.first else {
            scene.remove(id: id); return
        }
        multiPointLineId = id
        setAbsolutePoints(id, [start, start])  // committed start + preview point
        window?.acceptsMouseMovedEvents = true
        scene.selection = []
        updateSelectionState()
        renderer.invalidate(id)
        needsDisplay = true
    }

    /// A click while placing points: commit the preview as a real vertex (or
    /// finish if it lands on the last committed point / is a double-click).
    private func handleMultiPointClick(at p: CGPoint, doubleClick: Bool) {
        guard let id = multiPointLineId, let e = scene.element(id) else {
            multiPointLineId = nil; return
        }
        let pts = e.absolutePoints
        let committed = Array(pts.dropLast())   // all but the trailing preview
        if doubleClick || (committed.last.map { hypot(p.x - $0.x, p.y - $0.y) < 8 } ?? false) {
            finishMultiPointLine(); return
        }
        setAbsolutePoints(id, committed + [p, p])  // fix this vertex, start a new preview
        renderer.invalidate(id)
        needsDisplay = true
    }

    /// Commit the multi-point line: drop the trailing preview point, bind the
    /// endpoints to any shapes under them, and select it.
    private func finishMultiPointLine() {
        guard let id = multiPointLineId else { return }
        multiPointLineId = nil
        window?.acceptsMouseMovedEvents = false
        guard let e = scene.element(id) else { return }
        var pts = e.absolutePoints
        if pts.count >= 2 { pts.removeLast() }   // drop preview
        guard pts.count >= 2 else { scene.remove(id: id); needsDisplay = true; return }
        setAbsolutePoints(id, pts)
        bindEndpoint(id, isStart: true, at: pts.first!)
        bindEndpoint(id, isStart: false, at: pts.last!)
        rebuildArrow(id)
        scene.selection = [id]
        controller.tool = .select   // revert to the pointer after placing
        updateSelectionState()
        renderer.invalidate(id)
        needsDisplay = true
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
        e.simulatePressure = controller.style.pressureSensitive
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
        if e.type == "frame" {
            scene.sendToBack(id)            // frames sit behind their contents
        } else {
            reassignFrameMembership([id])   // drawn inside a frame → becomes a member
        }
        scene.selection = [id]
        controller.tool = .select   // revert to the pointer after placing
        updateSelectionState()
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
        updatePipeAnimation()
        needsDisplay = true
    }

    /// Select an element (by id) and center the camera on it, keeping the current
    /// zoom. Used by cross-board search to jump straight to a hit.
    func focusElement(_ id: String) {
        guard let e = scene.element(id) else { return }
        scene.selection = [id]
        let r = e.boundingRect
        let center = CGPoint(x: r.midX, y: r.midY)
        // `offset` is the scene point at the view's top-left; place the element's
        // center at the view's center (zoom unchanged).
        camera.offset = CGPoint(x: center.x - bounds.midX / camera.zoom,
                                y: center.y - bounds.midY / camera.zoom)
        updateSelectionState()
        needsDisplay = true
    }

    /// Drop a linked file node at the center of the current view.
    func addFileNode(path: String) {
        addLink(link: path, name: (path as NSString).lastPathComponent)
    }

    /// Insert an image element from a file path, sized to fit ~320pt.
    func addImage(path: String, at point: CGPoint? = nil) {
        guard let img = NSImage(contentsOfFile: (path as NSString).expandingTildeInPath),
              img.size.width > 0 else { return }
        let maxDim: CGFloat = 320
        let scale = min(1, maxDim / max(img.size.width, img.size.height))
        let w = img.size.width * scale, h = img.size.height * scale
        let center = point ?? camera.viewToScene(CGPoint(x: bounds.midX, y: bounds.midY))
        scene.beginEdit()
        var e = makeElement(type: "image", x: center.x - Double(w) / 2, y: center.y - Double(h) / 2,
                            width: Double(w), height: Double(h))
        e.link = path
        e.backgroundColor = "transparent"
        scene.add(e)
        scene.selection = [e.id]
        controller.tool = .select
        updateSelectionState()
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "bmp", "webp"]

    /// Drop a link node at a scene point (default view center). How it renders —
    /// QuickLook preview card, icon + name, or colored text — follows the
    /// `Settings.linkStyle` preference (URLs are always compact).
    func addLink(link: String, name: String, at point: CGPoint? = nil) {
        let center = point ?? camera.viewToScene(CGPoint(x: bounds.midX, y: bounds.midY))
        let isFilePath = !link.contains("://")
        scene.beginEdit()
        if isFilePath && Settings.linkStyle == "preview" {
            let w = 150.0, h = 172.0
            var e = makeElement(type: "file", x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
            e.text = name; e.link = link; e.backgroundColor = "#ffffff"
            scene.add(e); scene.selection = [e.id]
        } else {
            let size = 16.0
            var e = makeElement(type: "file", x: center.x, y: center.y, width: 10, height: size * 1.3)
            e.text = name; e.link = link; e.backgroundColor = "transparent"; e.fontSize = size
            let label = (Settings.linkStyle == "text" ? "" : e.linkDisplayIcon) + name
            let w = (label as NSString).size(withAttributes: [.font: Fonts.handDrawn(size: CGFloat(size))]).width
            e.x = center.x - Double(w) / 2; e.y = center.y - size * 1.3 / 2; e.width = Double(w) + 6
            scene.add(e); scene.selection = [e.id]
        }
        updateSelectionState()
    }

    /// Re-fit every file/link node to the current `Settings.linkStyle` (card vs
    /// compact), so toggling the preference updates existing nodes too.
    func restyleFileNodes() {
        let style = Settings.linkStyle
        scene.beginEdit()
        for e in scene.elements where e.type == "file" {
            let isFilePath = (e.link.map { !$0.contains("://") } ?? false)
            let center = CGPoint(x: e.rect.midX, y: e.rect.midY)
            if isFilePath && style == "preview" {
                let w = 150.0, h = 172.0
                scene.update(id: e.id) { el in
                    el.x = center.x - w / 2; el.y = center.y - h / 2; el.width = w; el.height = h
                    el.backgroundColor = "#ffffff"
                }
            } else {
                let size = CGFloat(e.fontSize ?? 16)
                let font = e.fontFamily.map { Fonts.font(family: $0, size: size) } ?? Fonts.handDrawn(size: size)
                let label = (style == "text" ? "" : e.linkDisplayIcon) + (e.text ?? "")
                let w = (label as NSString).size(withAttributes: [.font: font]).width
                scene.update(id: e.id) { el in
                    el.x = center.x - Double(w) / 2; el.y = center.y - Double(size) * 1.3 / 2
                    el.width = Double(w) + 6; el.height = Double(size) * 1.3
                    el.backgroundColor = "transparent"
                }
            }
            renderer.invalidate(e.id)
        }
        needsDisplay = true
    }

    private func openLink(_ link: String) {
        let url: URL? = link.contains("://")
            ? URL(string: link)
            : URL(fileURLWithPath: (link as NSString).expandingTildeInPath)
        if let url { NSWorkspace.shared.open(url) }
    }

    @objc private func thumbnailReady() { needsDisplay = true }

    // MARK: Finder — Quick Look & context menu

    /// The on-disk file URL of the single selected file/image node, if it exists.
    private func selectedFileURL() -> URL? {
        guard scene.selection.count == 1, let id = scene.selection.first, let e = scene.element(id),
              e.type == "file" || e.type == "image",
              let link = e.link, !link.contains("://") else { return nil }
        let path = (link as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private var quickLookURL: URL?

    private func toggleQuickLook() {
        guard let url = selectedFileURL(), let panel = QLPreviewPanel.shared() else { return }
        quickLookURL = url
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // These NSResponder overrides are delivered as nonisolated by the SDK, but
    // always run on the main thread — hop onto the main actor to touch the panel
    // and our state (an error under Swift 6.0, a warning under 6.3).
    override nonisolated func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
        }
    }
    override nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLookURL = nil }
    }

    private var contextPath: String?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard isEditing else { return nil }
        let p = camera.viewToScene(viewPoint(event))
        guard let hit = scene.hitTest(p, tolerance: 8 / camera.zoom),
              hit.type == "file" || hit.type == "image",
              let link = hit.link, !link.contains("://") else { return nil }
        scene.selection = [hit.id]; updateSelectionState(); needsDisplay = true
        contextPath = (link as NSString).expandingTildeInPath
        let menu = NSMenu()
        menu.addItem(withTitle: "Open", action: #selector(ctxOpen), keyEquivalent: "")
        menu.addItem(withTitle: "Quick Look", action: #selector(ctxQuickLook), keyEquivalent: "")
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(ctxReveal), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Delete", action: #selector(ctxDelete), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func ctxOpen() {
        if let p = contextPath { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
    }
    @objc private func ctxQuickLook() { toggleQuickLook() }
    @objc private func ctxReveal() {
        if let p = contextPath { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
    }
    @objc private func ctxDelete() { deleteSelectionAction() }

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
        controller.selectionCount = scene.selection.count
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
            if e.type == "freedraw" { controller.style.pressureSensitive = e.simulatePressure ?? true }
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
                if e.type == "line" || e.type == "arrow" {
                    // Edges toggle → smooth curve vs. sharp corners (elbow stays sharp).
                    e.roundness = (s.rounded && !e.elbowed) ? Element.Roundness(type: 2) : nil
                }
                if e.type == "freedraw" {
                    e.simulatePressure = s.pressureSensitive
                }
                if e.type == "text" {
                    e.fontSize = s.fontSize
                    e.fontFamily = s.fontFamily
                    let font = Fonts.font(family: s.fontFamily, size: CGFloat(s.fontSize))
                    let w = ((e.text ?? "") as NSString).size(withAttributes: [.font: font]).width
                    e.width = Double(w) + 8
                    e.height = s.fontSize * 1.25
                }
                if e.type == "file" {
                    e.fontSize = s.fontSize
                    e.fontFamily = s.fontFamily
                    // Compact link nodes (URLs) re-fit to the new font; file/folder
                    // cards keep their box and just restyle the caption.
                    let isCard = (e.link.map { !$0.contains("://") } ?? false)
                    if !isCard {
                        let font = Fonts.font(family: s.fontFamily, size: CGFloat(s.fontSize))
                        let display = e.linkDisplayIcon + (e.text ?? "")
                        let w = (display as NSString).size(withAttributes: [.font: font]).width
                        e.width = Double(w) + 6
                        e.height = s.fontSize * 1.3
                    }
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
                e.startBindingPoint = nil; e.endBindingPoint = nil
                scene.add(e)
                newIds.append(e.id)
            }
            // Offset the buffer so repeated pastes cascade.
            clipboard = clipboard.map { var c = $0; c.x += 20; c.y += 20; return c }
            scene.selection = Set(newIds)
        } else if let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
            let center = camera.viewToScene(CGPoint(x: bounds.midX, y: bounds.midY))
            // Tabular data → open the Liquid Glass wheel to pick a chart type.
            if let sheet = ChartMaker.parse(str) {
                chartWheel.present(options: chartWheelOptions()) { [weak self] choice in
                    guard let self, let choice else { return }   // cancelled
                    self.scene.beginEdit()
                    if choice == "text" {
                        self.insertTextBox(str, center: center)
                    } else {
                        self.insertChart(sheet, type: choice, center: center)
                    }
                }
                return
            }
            insertTextBox(str, center: center)
        }
        updateSelectionState()
    }

    private func insertTextBox(_ str: String, center: CGPoint) {
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
        updateSelectionState()
    }

    /// Chart types offered in the paste wheel, plus a "paste as text" escape.
    private func chartWheelOptions() -> [ChartWheelOption] {
        let titles = ["bar": "Bar", "line": "Line", "hbar": "Horizontal",
                      "step": "Step", "scatter": "Scatter", "lollipop": "Lollipop"]
        return ChartMaker.types.map { ChartWheelOption(type: $0, title: titles[$0] ?? $0.capitalized) }
            + [ChartWheelOption(type: "text", title: "Text")]
    }

    /// Add a generated chart's elements, grouped and selected.
    private func insertChart(_ sheet: ChartMaker.Spreadsheet, type: String, center: CGPoint) {
        let els = ChartMaker.elements(sheet, type: type, center: center)
        var ids = Set<String>()
        for e in els { scene.add(e); ids.insert(e.id) }
        scene.selection = ids
        controller.tool = .select
        updateSelectionState()
        needsDisplay = true
    }


    // MARK: Keyboard

    // Cmd-shortcuts arrive here (not keyDown). Without an app menu they'd
    // otherwise be dropped. Returning true marks them handled.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // While a text/code editor is focused, route clipboard + select-all +
        // undo to it (the canvas otherwise grabs ⌘C/V/X/A/Z for elements, and
        // there's no Edit menu to dispatch them, so paste would do nothing).
        if event.modifierFlags.contains(.command),
           let editor = window?.firstResponder as? NSText {
            switch event.charactersIgnoringModifiers {
            case "v": editor.paste(nil); return true
            case "c": editor.copy(nil); return true
            case "x": editor.cut(nil); return true
            case "a": editor.selectAll(nil); return true
            case "z":
                if event.modifierFlags.contains(.shift) { editor.undoManager?.redo() }
                else { editor.undoManager?.undo() }
                return true
            default: break
            }
        }
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
        case "g": shift ? ungroupSelection() : groupSelection(); needsDisplay = true; return true
        case "\r": shift ? runGraph() : runSelectedCell(); return true   // ⌘↵ cell, ⌘⇧↵ whole graph
        default: return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isEditing else { return super.keyDown(with: event) }
        // While placing a multi-point line, Return / Enter / Esc finish it.
        if multiPointLineId != nil, [36, 76, 53].contains(event.keyCode) {
            finishMultiPointLine(); return
        }
        if event.keyCode == 49 { // space → Quick Look a selected file, else arm pan
            if selectedFileURL() != nil { toggleQuickLook(); return }
            spaceDown = true; return
        }
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)
        // "?" opens the shortcuts window; "/" opens the file-link search.
        // (charactersIgnoringModifiers keeps Shift, so ⇧/ reads as "?", not "/".)
        if event.charactersIgnoringModifiers == "?" { controller.openShortcutsAction?(); return }
        if event.charactersIgnoringModifiers == "/" { onSlashSearch?(); return }
        // ⇧1 fits the whole board to the view.
        if shift, event.keyCode == 18 { zoomToFit(); return }
        if cmd, let ch = event.charactersIgnoringModifiers {
            switch ch {
            case "z": shift ? scene.redo() : scene.undo()
                      renderer.invalidateAll(); updateSelectionState(); return
            case "c": copySelection(); return
            case "x": copySelection(); deleteSelectionAction(); return
            case "v": paste(); return
            case "a": scene.selection = Set(scene.elements.map(\.id)); updateSelectionState(); needsDisplay = true; return
            case "0": resetZoom(); return
            case "=", "+":
                camera.zoom(by: 1.1, around: CGPoint(x: bounds.midX, y: bounds.midY)); needsDisplay = true; return
            case "-":
                camera.zoom(by: 1 / 1.1, around: CGPoint(x: bounds.midX, y: bounds.midY)); needsDisplay = true; return
            case "k": controller.linkURLAction?(); return
            case "f": controller.openSearchAction?(); return
            default: break
            }
        }
        // ⌥Arrow nudges the camera around the canvas.
        if option {
            switch event.keyCode {
            case 123: panCanvas(40, 0); return   // left
            case 124: panCanvas(-40, 0); return  // right
            case 126: panCanvas(0, 40); return   // up
            case 125: panCanvas(0, -40); return  // down
            default: break
            }
        }
        switch event.keyCode {
        case 51, 117: deleteSelectionAction(); return // delete / fwd-delete
        case 53: scene.selection.removeAll(); updateSelectionState(); needsDisplay = true; return // esc
        case 36, 76: editSelectedText(); return       // return / enter → edit selected text
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

    // MARK: Zoom & pan shortcuts

    /// Fit every element on the board into the view (⇧1), with a little padding.
    private func zoomToFit() {
        guard bounds.width > 0, bounds.height > 0, let content = Export.contentBounds(scene.elements) else { return }
        let z = max(Camera.minZoom, min(Camera.maxZoom,
                    min(bounds.width / (content.width + 80), bounds.height / (content.height + 80))))
        camera.zoom = z
        camera.offset = CGPoint(x: content.midX - (bounds.width / 2) / z,
                                y: content.midY - (bounds.height / 2) / z)
        needsDisplay = true
    }

    /// Reset to 1× while keeping whatever's at the view center in place (⌘0).
    private func resetZoom() {
        let c = camera.viewToScene(CGPoint(x: bounds.midX, y: bounds.midY))
        camera.zoom = 1
        camera.offset = CGPoint(x: c.x - bounds.midX, y: c.y - bounds.midY)
        needsDisplay = true
    }

    /// Nudge the camera by a view-space delta (⌥Arrow).
    private func panCanvas(_ dx: CGFloat, _ dy: CGFloat) {
        camera.pan(byViewDelta: CGSize(width: dx, height: dy))
        needsDisplay = true
    }

    /// Return / Enter on a single selected element edits its text.
    private func editSelectedText() {
        guard scene.selection.count == 1, let id = scene.selection.first, let e = scene.element(id) else { return }
        if e.type == "text" { beginEditingText(e) }
        else if ["rectangle", "ellipse", "diamond"].contains(e.type) { beginContainerText(e) }
        else if e.type == "cell" { beginEditingCell(e) }
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

    /// Add/edit text bound inside a shape (centered, wrapping to the shape).
    private func beginContainerText(_ shape: Element) {
        if let existing = scene.elements.first(where: { $0.type == "text" && $0.containerId == shape.id }) {
            beginEditingText(existing)
            return
        }
        scene.beginEdit()
        let r = shape.rect
        var e = makeElement(type: "text", x: r.minX, y: r.minY, width: r.width, height: r.height)
        e.text = ""
        e.fontSize = controller.style.fontSize
        e.fontFamily = controller.style.fontFamily
        e.strokeColor = controller.style.strokeColor
        e.containerId = shape.id
        e.textAlign = "center"
        e.verticalAlign = "middle"
        scene.add(e)
        scene.selection = [shape.id]
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
        let size = CGFloat(e.fontSize ?? 20) * camera.zoom
        let h = size + 8
        let frame: NSRect
        if e.containerId != nil {
            // Centered inside the container.
            let leftMid = camera.sceneToView(CGPoint(x: e.x, y: e.rect.midY))
            frame = NSRect(x: leftMid.x + 8, y: leftMid.y - h / 2,
                           width: max(40, e.width * camera.zoom - 16), height: h)
        } else {
            let origin = camera.sceneToView(CGPoint(x: e.x, y: e.y))
            frame = NSRect(x: origin.x, y: origin.y, width: max(240, e.width * camera.zoom + 40), height: h)
        }
        let field = NSTextField(frame: frame)
        if e.containerId != nil { field.alignment = .center }
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
            scene.update(id: id) { e in
                e.text = value
                if e.containerId == nil {  // free text hugs its content; bound text keeps the shape's box
                    let width = (value as NSString).size(withAttributes: [.font: Fonts.font(family: family, size: size)]).width
                    e.width = Double(width) + 8
                    e.height = Double(size) * 1.25
                }
            }
            renderer.invalidate(id)
        }
        field.removeFromSuperview()
        textField = nil
        editingTextId = nil
        controller.tool = .select
        needsDisplay = true
    }

    // MARK: Live cells

    private static func starterCode(_ lang: String) -> String {
        switch lang {
        case "python": return "import platform\nprint('Hello from', platform.system())\nprint('squares:', [x*x for x in range(8)])"
        case "javascript": return "console.log('Hello from Node', process.version)"
        case "ruby": return "puts \"Hello from Ruby #{RUBY_VERSION}\""
        default: return "echo \"Hello from Whitespace\"\ndate \"+%A %H:%M\""
        }
    }

    /// Drop a runnable cell at the view center.
    func insertCell(language: String = "shell") {
        let center = camera.viewToScene(CGPoint(x: bounds.midX, y: bounds.midY))
        scene.beginEdit()
        var e = makeElement(type: "cell", x: center.x - 230, y: center.y - 110, width: 460, height: 220)
        e.cellLanguage = language
        e.text = Self.starterCode(language)
        e.backgroundColor = "transparent"
        scene.add(e)
        scene.selection = [e.id]
        controller.tool = .select
        updateSelectionState()
        needsDisplay = true
    }

    /// The scene-space hit area for a cell's run glyph (header, top-right).
    private func cellRunHitRect(_ e: Element) -> CGRect {
        let r = e.rect
        return CGRect(x: r.maxX - 38, y: r.minY, width: 38, height: 28)
    }

    private func runSelectedCell() {
        if let id = editingCellId { commitCellEdit(); runCell(id); return }
        if let id = scene.selection.first(where: { scene.element($0)?.type == "cell" }) { runCell(id) }
    }

    /// Run one cell, piping its upstream cells' current output into its stdin.
    private func runCell(_ id: String) {
        guard let e = scene.element(id), e.type == "cell" else { return }
        let ups = incomingCells(of: id)
        let input = ups.map { scene.element($0)?.cellOutput ?? "" }.joined(separator: "\n")
        ups.forEach { pulsePipe(from: $0, to: id) }
        runningCells.insert(id)
        scene.update(id: id) { $0.cellOutput = "running…" }
        renderer.invalidate(id); needsDisplay = true
        CellRunner.run(language: e.cellLanguage ?? "shell", code: e.text ?? "", input: input) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.runningCells.remove(id)
                self.scene.update(id: id) { $0.cellOutput = result.output }
                self.renderer.invalidate(id)
                self.needsDisplay = true
                self.onSceneChange?()
            }
        }
    }

    // MARK: Dataflow graph

    private func cellIdSet() -> Set<String> { Set(scene.elements.filter { $0.type == "cell" }.map(\.id)) }

    /// Upstream cell ids feeding `id` (arrows bound cell→cell ending at `id`).
    private func incomingCells(of id: String) -> [String] {
        let cells = cellIdSet()
        return scene.elements.compactMap { a in
            guard a.type == "arrow" || a.type == "line", a.endBindingId == id,
                  let s = a.startBindingId, cells.contains(s) else { return nil }
            return s
        }
    }

    private func pipeArrowId(from: String, to: String) -> String? {
        scene.elements.first {
            ($0.type == "arrow" || $0.type == "line") && $0.startBindingId == from && $0.endBindingId == to
        }?.id
    }

    /// Kick a data pulse along the pipe from `from` to `to`.
    private func pulsePipe(from: String, to: String) {
        guard let aid = pipeArrowId(from: from, to: to) else { return }
        pipePulses[aid] = 0.0001
        renderer.pipePulses = pipePulses.mapValues { CGFloat($0) }
        updatePipeAnimation()
        needsDisplay = true
    }

    /// Run the whole graph: every cell in topological order, piping each cell's
    /// output into its downstream cells' stdin (⌘⇧↵).
    func runGraph() {
        let cells = cellIdSet()
        guard !cells.isEmpty else { return }
        var edges: [(String, String)] = []
        for a in scene.elements where a.type == "arrow" || a.type == "line" {
            if let s = a.startBindingId, let t = a.endBindingId, cells.contains(s), cells.contains(t) {
                edges.append((s, t))
            }
        }
        graphOrder = Self.topoSort(Array(cells), edges)
        graphOutputs = [:]
        runGraphStep(0)
    }

    private static func topoSort(_ nodes: [String], _ edges: [(String, String)]) -> [String] {
        var indeg = Dictionary(uniqueKeysWithValues: nodes.map { ($0, 0) })
        var adj: [String: [String]] = [:]
        for (s, t) in edges { adj[s, default: []].append(t); indeg[t, default: 0] += 1 }
        var queue = nodes.filter { indeg[$0] == 0 }
        var order: [String] = []
        while !queue.isEmpty {
            let n = queue.removeFirst(); order.append(n)
            for m in adj[n] ?? [] { indeg[m]! -= 1; if indeg[m] == 0 { queue.append(m) } }
        }
        for n in nodes where !order.contains(n) { order.append(n) }   // cycle leftovers
        return order
    }

    private func runGraphStep(_ i: Int) {
        guard i < graphOrder.count else { needsDisplay = true; return }
        let id = graphOrder[i]
        guard let cell = scene.element(id), cell.type == "cell" else { runGraphStep(i + 1); return }
        let ups = incomingCells(of: id)
        let input = ups.map { graphOutputs[$0] ?? "" }.joined(separator: "\n")
        ups.forEach { pulsePipe(from: $0, to: id) }
        scene.update(id: id) { $0.cellOutput = "running…" }
        renderer.invalidate(id); needsDisplay = true
        CellRunner.run(language: cell.cellLanguage ?? "shell", code: cell.text ?? "", input: input) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.graphOutputs[id] = result.output
                self.scene.update(id: id) { $0.cellOutput = result.output }
                self.renderer.invalidate(id); self.needsDisplay = true; self.onSceneChange?()
                // Brief pause so the pulse into the next cell reads clearly.
                Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.runGraphStep(i + 1) }
                }
            }
        }
    }

    private func beginEditingCell(_ e: Element) {
        commitText(); commitCellEdit()
        scene.selection = [e.id]
        updateSelectionState()
        let r = e.rect
        let topLeft = camera.sceneToView(CGPoint(x: r.minX, y: r.minY + 26))
        let w = e.width * camera.zoom
        let codeH = max(60, (e.height - 26) * camera.zoom * 0.62)
        let scroll = NSScrollView(frame: NSRect(x: topLeft.x, y: topLeft.y, width: w, height: codeH))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(hex: 0x1e1e2e)
        let tv = CodeTextView(frame: NSRect(origin: .zero, size: scroll.frame.size))
        tv.string = e.text ?? ""
        tv.font = NSFont.monospacedSystemFont(ofSize: 12.5 * camera.zoom, weight: .regular)
        tv.textColor = NSColor(hex: 0xe4e4ef)
        tv.backgroundColor = NSColor(hex: 0x1e1e2e)
        tv.insertionPointColor = .white
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.textContainerInset = NSSize(width: 6, height: 4)
        tv.onRun = { [weak self] in self?.runSelectedCell() }
        scroll.documentView = tv
        addSubview(scroll)
        window?.makeFirstResponder(tv)
        cellScroll = scroll; cellEditor = tv; editingCellId = e.id
    }

    /// True when any arrow connects two cells (a live data pipe).
    private func hasLivePipes() -> Bool {
        let cells = Set(scene.elements.filter { $0.type == "cell" }.map(\.id))
        guard !cells.isEmpty else { return false }
        return scene.elements.contains { e in
            guard e.type == "arrow" || e.type == "line",
                  let s = e.startBindingId, let t = e.endBindingId else { return false }
            return cells.contains(s) && cells.contains(t)
        }
    }

    /// Run a low-rate timer that animates the marching-ants flow on live pipes,
    /// only while at least one exists.
    private func updatePipeAnimation() {
        let live = hasLivePipes()
        if live, pipeTimer == nil {
            pipeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.renderer.pipePhase += 0.9
                    if !self.pipePulses.isEmpty {
                        for (k, v) in self.pipePulses {
                            let nv = v + 0.045
                            if nv >= 1 { self.pipePulses[k] = nil } else { self.pipePulses[k] = nv }
                        }
                        self.renderer.pipePulses = self.pipePulses.mapValues { CGFloat($0) }
                    }
                    self.needsDisplay = true
                }
            }
        } else if !live, let t = pipeTimer {
            t.invalidate(); pipeTimer = nil
        }
    }

    private func commitCellEdit() {
        guard let tv = cellEditor, let id = editingCellId else { return }
        let value = tv.string
        scene.update(id: id) { $0.text = value }
        renderer.invalidate(id)
        cellScroll?.removeFromSuperview()
        cellScroll = nil; cellEditor = nil; editingCellId = nil
        needsDisplay = true
    }
}

extension CanvasView: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { quickLookURL == nil ? 0 : 1 }
    }
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { quickLookURL as NSURL? }
    }
}
