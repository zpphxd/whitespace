import AppKit
import CoreImage

/// Generate a QR code image from a string (URL, app link, or any text). Uses the
/// built-in CoreImage generator — no dependencies.
enum QRCode {
    /// Render a crisp QR PNG for `string`, save it under the workspace's images
    /// folder, and return the file path (or nil on failure).
    static func generatePNG(for string: String) -> String? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")   // 15% error correction
        guard let output = filter.outputImage else { return nil }

        // The generator emits ~25px modules; scale up nearest-neighbor for sharp edges.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }

        let path = Workspace.imagesDir.appendingPathComponent("qr-\(UUID().uuidString).png")
        do { try png.write(to: path); return path.path } catch { return nil }
    }
}
