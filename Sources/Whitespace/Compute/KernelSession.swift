import Foundation

/// Our own lightweight "kernel": a long-lived interpreter process per language
/// whose namespace is shared across cell runs (so `x = 1` in one cell is visible
/// in the next — the Jupyter leap). Code is fed over a one-line base64 protocol;
/// each run's output is terminated by a unique result marker.
///
/// Runs the user's own code on their machine — only from an explicit Run action.
final class KernelSession: @unchecked Sendable {
    static let marker = "__WS_RESULT_9f3a2b__"

    let language: String
    private let proc = Process()
    private let inPipe = Pipe()
    private let outPipe = Pipe()
    private let queue = DispatchQueue(label: "whitespace.kernel")
    private var acc = Data()
    private var pendingOutput = ""
    private var current: (@Sendable (String, Bool) -> Void)?
    private var waiting: [(inB: String, codeB: String, done: @Sendable (String, Bool) -> Void)] = []

    init?(language: String) {
        self.language = language
        guard let (path, driver) = Self.driver(for: language) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws_kernel_\(language)_\(UUID().uuidString)")
        guard (try? driver.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }

        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = [url.path]
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = outPipe
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            self?.queue.async { self?.ingest(d) }
        }
        do { try proc.run() } catch { return nil }
    }

    func stop() {
        outPipe.fileHandleForReading.readabilityHandler = nil
        proc.terminate()
    }

    /// Run `code` with `input` exposed as the `IN` variable in the shared namespace.
    func run(input: String, code: String, completion: @escaping @Sendable (String, Bool) -> Void) {
        let inB = Data(input.utf8).base64EncodedString()
        let codeB = Data(code.utf8).base64EncodedString()
        queue.async {
            self.waiting.append((inB, codeB, completion))
            self.runNext()
        }
    }

    // MARK: - Queue plumbing (all on `queue`)

    private func runNext() {
        guard current == nil, !waiting.isEmpty else { return }
        let job = waiting.removeFirst()
        current = job.done
        pendingOutput = ""
        let req = String(UUID().uuidString.prefix(8))
        let cmd = "__WS_EXEC__ \(req) \(job.inB) \(job.codeB)\n"
        inPipe.fileHandleForWriting.write(Data(cmd.utf8))
    }

    private func ingest(_ d: Data) {
        acc.append(d)
        while let nl = acc.firstIndex(of: 0x0A) {
            let lineData = acc[acc.startIndex..<nl]
            acc.removeSubrange(acc.startIndex...nl)
            let line = String(decoding: lineData, as: UTF8.self)
            if line.hasPrefix(Self.marker) {
                let parts = line.split(separator: " ")
                let failed = parts.count >= 3 ? parts[2] != "ok" : false
                let out = pendingOutput.trimmingCharacters(in: .newlines)
                pendingOutput = ""
                let done = current
                current = nil
                DispatchQueue.main.async { done?(out.isEmpty ? "(no output)" : out, failed) }
                runNext()
            } else {
                pendingOutput += line + "\n"
            }
        }
    }

    // MARK: - Drivers

    /// Interpreter path + the driver source that implements the exec loop.
    private static func driver(for language: String) -> (path: String, driver: String)? {
        switch language {
        case "python": return which("python3").map { ($0, pythonDriver) } ?? ("/usr/bin/python3", pythonDriver)
        case "javascript": return which("node").map { ($0, nodeDriver) }
        case "ruby": return which("ruby").map { ($0, rubyDriver) } ?? ("/usr/bin/ruby", rubyDriver)
        default: return ("/bin/zsh", shellDriver)
        }
    }

    private static func which(_ tool: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
            let p = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    private static let pythonDriver = """
    import sys, base64, io, traceback
    ns = {"__name__": "__main__"}
    for raw in sys.stdin:
        line = raw.rstrip("\\n")
        if not line.startswith("__WS_EXEC__ "):
            continue
        parts = line.split(" ", 3)
        reqid = parts[1]
        ns["IN"] = base64.b64decode(parts[2]).decode("utf-8", "replace")
        code = base64.b64decode(parts[3]).decode("utf-8", "replace")
        buf = io.StringIO()
        old_o, old_e = sys.stdout, sys.stderr
        sys.stdout = buf; sys.stderr = buf
        status = "ok"
        try:
            exec(compile(code, "<cell>", "exec"), ns)
        except Exception:
            traceback.print_exc()
            status = "error"
        finally:
            sys.stdout, sys.stderr = old_o, old_e
        sys.stdout.write(buf.getvalue())
        sys.stdout.write("\\n%s %s %s\\n" % ("__WS_RESULT_9f3a2b__", reqid, status))
        sys.stdout.flush()
    """

    private static let nodeDriver = """
    const vm = require('vm');
    let buf = '';
    const cons = {
      log: (...a) => { buf += a.map(x => typeof x === 'object' ? JSON.stringify(x) : String(x)).join(' ') + '\\n'; },
    };
    cons.error = cons.log; cons.warn = cons.log; cons.info = cons.log;
    const ctx = vm.createContext({ console: cons, require, process, Buffer, IN: '', global: {} });
    require('readline').createInterface({ input: process.stdin }).on('line', (line) => {
      if (!line.startsWith('__WS_EXEC__ ')) return;
      const p = line.split(' ');
      ctx.IN = Buffer.from(p[2], 'base64').toString('utf8');
      const code = Buffer.from(p[3], 'base64').toString('utf8');
      buf = ''; let status = 'ok';
      try { vm.runInContext(code, ctx, { displayErrors: true }); }
      catch (e) { buf += ((e && e.stack) ? e.stack : String(e)) + '\\n'; status = 'error'; }
      process.stdout.write(buf);
      process.stdout.write('\\n__WS_RESULT_9f3a2b__ ' + p[1] + ' ' + status + '\\n');
    });
    """

    private static let rubyDriver = """
    require "base64"
    require "stringio"
    while (line = STDIN.gets)
      line = line.chomp
      next unless line.start_with?("__WS_EXEC__ ")
      _, reqid, inb, codeb = line.split(" ", 4)
      code = Base64.decode64(codeb).force_encoding("UTF-8")
      input = Base64.decode64(inb).force_encoding("UTF-8")
      buf = StringIO.new
      old_o, old_e = $stdout, $stderr
      $stdout = buf; $stderr = buf
      status = "ok"
      begin
        TOPLEVEL_BINDING.local_variable_set(:IN, input)
        eval(code, TOPLEVEL_BINDING)
      rescue Exception => e
        buf.puts "#{e.class}: #{e.message}"
        status = "error"
      ensure
        $stdout = old_o; $stderr = old_e
      end
      print buf.string
      puts "\\n__WS_RESULT_9f3a2b__ #{reqid} #{status}"
      STDOUT.flush
    end
    """

    private static let shellDriver = """
    while IFS= read -r line; do
      case "$line" in __WS_EXEC__*) ;; *) continue ;; esac
      set -- $line
      IN="$(printf %s "$3" | base64 --decode)"; export IN
      code="$(printf %s "$4" | base64 --decode)"
      if eval "$code"; then st=ok; else st=error; fi
      echo "__WS_RESULT_9f3a2b__ $2 $st"
    done
    """
}

/// Manages one persistent session per language. Cells of the same language share
/// state; "restart" drops the session so the next run starts fresh.
@MainActor
final class Kernels {
    static let shared = Kernels()
    private var sessions: [String: KernelSession] = [:]

    private func session(_ language: String) -> KernelSession? {
        if let s = sessions[language] { return s }
        guard let s = KernelSession(language: language) else { return nil }
        sessions[language] = s
        return s
    }

    func run(language: String, code: String, input: String,
             completion: @escaping @Sendable (String, Bool) -> Void) {
        guard let s = session(language) else {
            completion("\(CellRunner.displayName(language)) interpreter not found.", true); return
        }
        s.run(input: input, code: code, completion: completion)
    }

    func restart(_ language: String) { sessions[language]?.stop(); sessions[language] = nil }
    func restartAll() { sessions.values.forEach { $0.stop() }; sessions.removeAll() }
}
