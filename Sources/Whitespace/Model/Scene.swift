import CoreGraphics
import Foundation

/// Runtime document state: the ordered element list (back-to-front), the
/// selection, and a snapshot-based undo/redo stack. Mutations bump the
/// element's `version` so the render cache knows to regenerate its path.
final class Scene {
    private(set) var elements: [Element]
    var selection: Set<String> = []

    private var undoStack: [[Element]] = []
    private var redoStack: [[Element]] = []
    private let undoLimit = 200

    var onChange: (() -> Void)?

    init(elements: [Element] = []) {
        self.elements = elements
    }

    // MARK: Undo grouping

    /// Snapshot current state before a discrete edit so it can be undone.
    func beginEdit() {
        undoStack.append(elements)
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(elements)
        elements = prev
        selection.formIntersection(Set(elements.map(\.id)))
        notify()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(elements)
        elements = next
        notify()
    }

    // MARK: Mutations

    func add(_ element: Element) {
        elements.append(element)
        notify()
    }

    func replaceLast(_ element: Element) {
        guard !elements.isEmpty else { return }
        elements[elements.count - 1] = element
        notify()
    }

    func update(id: String, _ mutate: (inout Element) -> Void) {
        guard let i = elements.firstIndex(where: { $0.id == id }) else { return }
        mutate(&elements[i])
        elements[i].version += 1
        elements[i].versionNonce = Int.random(in: 1...2_000_000_000)
        notify()
    }

    func remove(id: String) {
        elements.removeAll { $0.id == id }
        selection.remove(id)
        notify()
    }

    func removeSelected() {
        guard !selection.isEmpty else { return }
        elements.removeAll { selection.contains($0.id) }
        selection.removeAll()
        notify()
    }

    func index(of id: String) -> Int? { elements.firstIndex { $0.id == id } }

    func element(_ id: String) -> Element? { elements.first { $0.id == id } }

    func bringToFront(_ id: String) {
        guard let i = index(of: id) else { return }
        let e = elements.remove(at: i)
        elements.append(e)
        notify()
    }

    func sendToBack(_ id: String) {
        guard let i = index(of: id) else { return }
        let e = elements.remove(at: i)
        elements.insert(e, at: 0)
        notify()
    }

    /// Topmost element hit by a scene-space point.
    func hitTest(_ p: CGPoint, tolerance: CGFloat) -> Element? {
        for e in elements.reversed() where !e.locked {
            if e.hitTest(p, tolerance: tolerance) { return e }
        }
        return nil
    }

    /// Elements whose bounding box intersects a scene-space marquee rect.
    func elements(in rect: CGRect) -> [Element] {
        elements.filter { rect.intersects($0.boundingRect) }
    }

    private func notify() { onChange?() }
}
