import Foundation

/// Minimal file logger for diagnostics (the app runs detached, so stdout is not
/// visible). Writes to /tmp/whitespace.log.
enum Log {
    private static let url = URL(fileURLWithPath: "/tmp/whitespace.log")

    static func write(_ message: String) {
        let line = "\(message)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
