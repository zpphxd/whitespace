import AppKit
import QuickLookThumbnailing

/// Generates and caches QuickLook thumbnails for file/folder nodes. Returns the
/// system file icon immediately and upgrades to a rich QuickLook preview (PDF
/// first page, image, app icon, …) in the background, posting `readyNotification`
/// when one arrives so the canvas can redraw.
///
/// `@unchecked Sendable`: all mutable state is guarded by `lock`, so instances
/// are safe to touch from the QuickLook completion handler's background thread.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    static let readyNotification = Notification.Name("WhitespaceThumbnailReady")

    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]
    private var inflight: Set<String> = []

    /// A cached thumbnail if ready, else the system file icon now (with a
    /// background QuickLook request kicked off once per path).
    func image(for path: String, pixelSize: CGSize) -> NSImage? {
        let expanded = (path as NSString).expandingTildeInPath
        lock.lock()
        if let img = cache[expanded] { lock.unlock(); return img }
        let alreadyRequested = inflight.contains(expanded)
        let exists = FileManager.default.fileExists(atPath: expanded)
        if !alreadyRequested && exists { inflight.insert(expanded) }
        lock.unlock()

        if !alreadyRequested && exists {
            let url = URL(fileURLWithPath: expanded)
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let req = QLThumbnailGenerator.Request(fileAt: url, size: pixelSize, scale: scale,
                                                   representationTypes: .all)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
                guard let rep else { return }
                let image = rep.nsImage
                self.lock.lock()
                self.cache[expanded] = image
                self.inflight.remove(expanded)
                self.lock.unlock()
                // Post on main so observers (the canvas) redraw on the main thread.
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: ThumbnailCache.readyNotification, object: nil)
                }
            }
        }
        return NSWorkspace.shared.icon(forFile: expanded)
    }
}
