import AppKit

/// Dev harness: run a few live cells through `CellRunner`, render them to a PNG,
/// and print the captured output. `--run-cell-test <dir>`. Verifies both the
/// execution engine and the cell rendering without needing the live UI.
enum RunCellTest {
    static func run(to dir: String) {
        let snippets: [(String, String)] = [
            ("shell", "echo \"hello from the shell\"\nuname -m"),
            ("python", "import math\nprint('pi =', round(math.pi, 4))\nprint([x*x for x in range(5)])"),
            ("javascript", "console.log('node says:', [1,2,3].map(x => x*x))"),
        ]
        // Verify piping: upstream output → downstream stdin.
        let upstream = CellRunner.runSync(language: "shell", code: "seq 1 5")
        let downstream = CellRunner.runSync(language: "python",
            code: "import sys; print('sum =', sum(int(x) for x in sys.stdin))", input: upstream.output)
        FileHandle.standardError.write(Data("PIPE TEST → \(downstream.output)".utf8))
        let inEnv = CellRunner.runSync(language: "shell", code: "echo \"got: $IN\"", input: "hello-from-IN")
        FileHandle.standardError.write(Data("ENV  TEST → \(inEnv.output)---\n".utf8))

        var els: [Element] = []
        var y = 60.0
        for (lang, code) in snippets {
            let result = CellRunner.runSync(language: lang, code: code)
            FileHandle.standardError.write(Data("[\(lang)] failed=\(result.failed)\n\(result.output)\n---\n".utf8))
            var cell = Element(type: "cell", x: 60, y: y, width: 460, height: 200, seed: 1)
            cell.text = code
            cell.cellLanguage = lang
            cell.cellOutput = result.output
            els.append(cell)
            y += 230
        }
        // Two cells joined by a live pipe (arrow bound cell→cell), to verify the
        // pipe rendering.
        var src = Element(type: "cell", x: 60, y: y, width: 300, height: 150, seed: 2)
        src.cellLanguage = "shell"; src.text = "seq 1 5"; src.cellOutput = "1\n2\n3\n4\n5"
        var dst = Element(type: "cell", x: 540, y: y + 30, width: 300, height: 150, seed: 3)
        dst.cellLanguage = "python"; dst.text = "import sys\nprint(sum(int(x) for x in sys.stdin))"
        dst.cellOutput = "15"
        var pipe = Element(type: "arrow", x: 360, y: y + 75, seed: 4, endArrowhead: "arrow")
        pipe.points = [[0, 0], [180, 30]]
        pipe.startBindingId = src.id; pipe.endBindingId = dst.id
        els.append(src); els.append(dst); els.append(pipe)

        if let png = Export.png(els) {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("cells.png")
            try? png.write(to: url)
            FileHandle.standardError.write(Data("PNG \(png.count) bytes -> \(url.path)\n".utf8))
        }
    }
}
