import Foundation

/// Executes a live cell's source with the local interpreter and returns its
/// combined output. The source is passed as an argument (`-c` / `-e`) so the
/// process's **stdin is free** to receive upstream output — that's what makes
/// arrows-as-pipes work. Upstream output is also exposed as `$IN`.
///
/// Runs the user's own code on their machine — only ever from an explicit Run
/// action, never automatically on load.
enum CellRunner {

    struct Result {
        var output: String          // combined stdout (+ stderr)
        var failed: Bool            // non-zero exit or launch failure
    }

    static let languages = ["shell", "python", "javascript", "ruby"]

    static func displayName(_ lang: String) -> String {
        switch lang {
        case "python": return "Python"
        case "javascript": return "JavaScript"
        case "ruby": return "Ruby"
        default: return "Shell"
        }
    }

    /// Executable + args that run `code` from an argument, leaving stdin free.
    private static func launch(for lang: String, code: String) -> (path: String, args: [String])? {
        switch lang {
        case "python": return (which("python3") ?? "/usr/bin/python3", ["-c", code])
        case "javascript": return which("node").map { ($0, ["-e", code]) }
        case "ruby": return (which("ruby") ?? "/usr/bin/ruby", ["-e", code])
        default: return ("/bin/zsh", ["-c", code])
        }
    }

    /// Run `code` with `input` piped to stdin; call `completion` on the main thread.
    static func run(language: String, code: String, input: String = "",
                    completion: @escaping @Sendable (Result) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = runSync(language: language, code: code, input: input)
            DispatchQueue.main.async { completion(r) }
        }
    }

    /// Synchronous execution (blocks the caller). Feeds `input` to stdin and as `$IN`.
    static func runSync(language: String, code: String, input: String = "") -> Result {
        guard let launch = launch(for: language, code: code) else {
            return Result(output: "\(displayName(language)) interpreter not found.", failed: true)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launch.path)
        proc.arguments = launch.args
        var env = ProcessInfo.processInfo.environment
        env["IN"] = input
        proc.environment = env
        let outPipe = Pipe(), inPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = outPipe              // fold stderr into the same stream
        proc.standardInput = inPipe
        do {
            try proc.run()
            // Write input off-thread so a program that never reads stdin can't
            // deadlock us on a full pipe buffer.
            let writeH = inPipe.fileHandleForWriting
            DispatchQueue.global().async {
                if !input.isEmpty { writeH.write(Data(input.utf8)) }
                try? writeH.close()
            }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            return Result(output: text.isEmpty ? "(no output)" : text,
                          failed: proc.terminationStatus != 0)
        } catch {
            return Result(output: "Failed to launch: \(error.localizedDescription)", failed: true)
        }
    }

    private static func which(_ tool: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
            let p = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
}
