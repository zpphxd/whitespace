import AppKit

/// Builds a one-board "feature tour" that exercises the major capabilities added
/// to Whitespace: sketchy shapes + fills, smart curved connectors welded to
/// shapes, the pressure-variable freehand pen, paste-to-charts, one-click QR,
/// and the executable notebook (a live pipeline of runnable cells with a rich
/// table output and a pass/fail test cell). Saves a real `.excalidraw`
/// (openable + runnable in Whitespace) plus a PNG preview.
/// Dev harness: `--build-demo <dir>`.
enum DemoBoard {
    static func buildAndSave(to dir: String) {
        let els = elements()
        let base = URL(fileURLWithPath: dir)
        let doc = base.appendingPathComponent("Whitespace-Tour.excalidraw")
        DocumentStore.save(els, to: doc)
        if let png = Export.png(els) {
            try? png.write(to: base.appendingPathComponent("whitespace-tour.png"))
        }
        FileHandle.standardError.write(Data("saved \(doc.path)\n".utf8))
    }

    static func elements() -> [Element] {
        var els: [Element] = []
        let blue = "#a5d8ff", green = "#b2f2bb", violet = "#d0bfff", pink = "#fcc2d7", orange = "#ffd8a8"

        // ── Shared builders ─────────────────────────────────────────────
        @discardableResult
        func box(_ r: CGRect, _ text: String, _ fill: String, dia: Bool = false,
                 fillStyle: FillStyle = .solid, size: Double = 15) -> String {
            var e = Element(type: dia ? "diamond" : "rectangle", x: r.minX, y: r.minY,
                            width: r.width, height: r.height, backgroundColor: fill,
                            fillStyle: fillStyle, opacity: 100)
            if !dia { e.roundness = Element.Roundness(type: 3) }
            els.append(e)
            if !text.isEmpty {
                var lab = Element(type: "text", x: r.minX, y: r.minY, width: r.width, height: r.height,
                                  opacity: 100, text: text, fontSize: size, textAlign: "center", verticalAlign: "middle")
                lab.containerId = e.id
                els.append(lab)
            }
            return e.id
        }
        func title(_ text: String, _ x: Double, _ y: Double, _ w: Double, size: Double = 30, color: String = "#1e1e1e") {
            els.append(Element(type: "text", x: x, y: y, width: w, height: size * 1.4, strokeColor: color,
                               opacity: 100, text: text, fontSize: size, textAlign: "left", verticalAlign: "top"))
        }
        func note(_ text: String, _ x: Double, _ y: Double, _ w: Double = 260, size: Double = 13, color: String = "#495057") {
            els.append(Element(type: "text", x: x, y: y, width: w, height: size * 1.4, strokeColor: color,
                               opacity: 100, text: text, fontSize: size, textAlign: "left", verticalAlign: "top"))
        }
        func frame(_ r: CGRect, _ label: String) {
            var f = Element(type: "frame", x: r.minX, y: r.minY, width: r.width, height: r.height, opacity: 100)
            f.text = label
            els.append(f)
        }
        /// Straight bound arrow that welds to the shapes' edges and follows them.
        func link(_ a: String, _ b: String, dashed: Bool = false,
                  from fp: [Double]? = nil, to tp: [Double]? = nil) {
            guard let sa = els.first(where: { $0.id == a }), let sb = els.first(where: { $0.id == b }) else { return }
            let fe = ArrowBinding.edgePoint(of: sa, toward: CGPoint(x: sb.rect.midX, y: sb.rect.midY))
            let te = ArrowBinding.edgePoint(of: sb, toward: CGPoint(x: sa.rect.midX, y: sa.rect.midY))
            var ar = Element(type: "arrow", x: Double(fe.x), y: Double(fe.y),
                             strokeStyle: dashed ? .dashed : .solid, opacity: 100, endArrowhead: "arrow")
            ar.points = [[0, 0], [Double(te.x - fe.x), Double(te.y - fe.y)]]
            ar.startBindingId = a; ar.endBindingId = b
            ar.startBindingPoint = fp; ar.endBindingPoint = tp
            els.append(ar)
        }
        @discardableResult
        func cell(_ r: CGRect, _ lang: String, _ code: String, _ out: CellRunner.Result,
                  test: Bool = false) -> String {
            var e = Element(type: "cell", x: r.minX, y: r.minY, width: r.width, height: r.height, opacity: 100)
            e.cellLanguage = lang; e.text = code; e.cellOutput = out.output
            e.cellFailed = out.failed
            if test { e.cellKind = "test" }
            els.append(e)
            return e.id
        }

        // ── Title ───────────────────────────────────────────────────────
        title("✦  Whitespace — a whiteboard that runs", 90, 30, 1100, size: 34)
        note("Native macOS · rough.js sketchy look · lives on your desktop · Excalidraw-compatible files",
             92, 78, 900, size: 15, color: "#6965db")

        // ── 1 · Sketchy shapes & fills ──────────────────────────────────
        frame(CGRect(x: 90, y: 130, width: 470, height: 300), "1 · Sketchy shapes & fills")
        box(CGRect(x: 120, y: 185, width: 130, height: 90), "rounded\nrectangle", blue, fillStyle: .hachure)
        box(CGRect(x: 285, y: 185, width: 120, height: 90), "ellipse", green, fillStyle: .solid)
        box(CGRect(x: 300, y: 185, width: 120, height: 90), "", "transparent") // spacer keeps ellipse readable
        // real ellipse on top of the placeholder slot
        do {
            var e = Element(type: "ellipse", x: 285, y: 185, width: 120, height: 90,
                            backgroundColor: green, fillStyle: .solid, opacity: 100)
            els.append(e)
            var lab = Element(type: "text", x: 285, y: 185, width: 120, height: 90, opacity: 100,
                              text: "ellipse", fontSize: 15, textAlign: "center", verticalAlign: "middle")
            lab.containerId = e.id; els.append(lab)
        }
        box(CGRect(x: 430, y: 185, width: 110, height: 100), "diamond", violet, dia: true)
        note("hachure · solid · cross-hatch fills, stable seeded jitter", 120, 300, 420)
        note("8 tools · inspector for stroke / fill / roughness / opacity", 120, 326, 420)
        note("colors from the Open-Color palette", 120, 352, 420)

        // ── 2 · Smart connectors ────────────────────────────────────────
        frame(CGRect(x: 590, y: 130, width: 500, height: 300), "2 · Smart connectors")
        let n1 = box(CGRect(x: 630, y: 190, width: 120, height: 60), "Design", pink)
        let n2 = box(CGRect(x: 930, y: 185, width: 120, height: 60), "Build", orange)
        let n3 = box(CGRect(x: 780, y: 320, width: 120, height: 60), "Ship", green)
        // Straight welded arrow (fixed-point weld: right-middle → left-middle).
        link(n1, n2, from: [1.0, 0.5], to: [0.0, 0.5])
        // Curved multi-point connector (roundness type 2 = Catmull-Rom curve).
        do {
            let ea = els.first { $0.id == n2 }!, eb = els.first { $0.id == n3 }!
            let s = ArrowBinding.edgePoint(of: ea, toward: CGPoint(x: eb.rect.midX, y: eb.rect.midY))
            let t = ArrowBinding.edgePoint(of: eb, toward: CGPoint(x: ea.rect.midX, y: ea.rect.midY))
            var ar = Element(type: "arrow", x: Double(s.x), y: Double(s.y), opacity: 100, endArrowhead: "arrow")
            ar.roundness = Element.Roundness(type: 2)
            ar.points = [[0, 0], [Double((t.x - s.x) * 0.35), Double((t.y - s.y) * 0.15) - 40],
                         [Double(t.x - s.x), Double(t.y - s.y)]]
            ar.startBindingId = n2; ar.endBindingId = n3
            els.append(ar)
        }
        link(n1, n3, dashed: true)
        note("arrows weld to a fixed point on the shape and follow it when you", 620, 392, 460)
        note("move or resize · straight, curved, and multi-point connectors", 620, 410, 460)

        // ── 3 · Pressure pen ────────────────────────────────────────────
        frame(CGRect(x: 90, y: 460, width: 470, height: 250), "3 · Pressure pen")
        func stroke(_ x: Double, _ y: Double, uniform: Bool, color: String) {
            var pts: [[Double]] = []
            let n = 48
            for i in 0...n {
                let t = Double(i) / Double(n)
                // Uniform: even spacing (constant speed). Variable: accelerating
                // spacing (speeds up → perfect-freehand tapers it thinner).
                let px = (uniform ? t : t * t) * 300
                let py = sin(t * .pi * 3) * 20
                pts.append([px, py])
            }
            var e = Element(type: "freedraw", x: x, y: y, width: 300, height: 50,
                            strokeColor: color, strokeWidth: uniform ? 4 : 7, opacity: 100)
            e.points = pts
            e.simulatePressure = uniform ? false : true
            els.append(e)
        }
        stroke(130, 545, uniform: false, color: "#e03131")
        stroke(130, 630, uniform: true, color: "#1971c2")
        note("variable — width follows speed (thick slow → thin fast)", 130, 560, 400, color: "#e03131")
        note("uniform — one constant thickness, your choice", 130, 645, 400, color: "#1971c2")

        // ── 4 · Paste → charts (each chart is ~276×280, so give it room) ──
        frame(CGRect(x: 590, y: 460, width: 850, height: 320), "4 · Paste data → charts")
        let data = "Month\tRevenue\nJan\t42\nFeb\t58\nMar\t50\nApr\t74\nMay\t66\nJun\t91"
        if let sheet = ChartMaker.parse(data) {
            els += ChartMaker.elements(sheet, type: "bar", center: CGPoint(x: 770, y: 615))
            els += ChartMaker.elements(sheet, type: "line", center: CGPoint(x: 1200, y: 615))
        }
        note("paste a spreadsheet, pick a type from the Liquid Glass wheel — bar · line · area · scatter · lollipop · horizontal bar",
             620, 752, 800)

        // ── 5 · One-click QR ────────────────────────────────────────────
        frame(CGRect(x: 1120, y: 130, width: 320, height: 300), "5 · Link → QR")
        let qrURL = "https://github.com/excalidraw/excalidraw"
        if let qr = QRCode.generatePNG(for: qrURL) {
            var e = Element(type: "image", x: 1210, y: 175, width: 150, height: 150, opacity: 100)
            e.link = qr; e.backgroundColor = "transparent"
            els.append(e)
        }
        note("type or paste a URL and it auto-links.", 1140, 345, 280)
        note("One click turns the link into a QR code.", 1140, 365, 280)
        note("Export the whole board to HTML with a", 1140, 393, 280, color: "#6965db")
        note("hidden, agent-readable data layer.", 1140, 411, 280, color: "#6965db")

        // ── 6 · Executable notebook (live pipeline) ─────────────────────
        frame(CGRect(x: 90, y: 810, width: 1350, height: 360), "6 · Executable notebook — cells run on your machine (⌘⇧↵)")
        title("▶ Live pipeline — arrows are pipes, kernels keep state", 120, 827, 900, size: 18, color: "#0b7285")

        let genCode = """
        # emit a small sales log: "month revenue"
        printf "Jan 42\\nFeb 58\\nMar 50\\nApr 74\\nMay 66\\nJun 91\\n"
        """
        let statsCode = """
        import sys
        rows = [l.split() for l in sys.stdin if l.strip()]
        vals = [int(r[1]) for r in rows]
        print(f"n      {len(vals)}")
        print(f"total  {sum(vals)}")
        print(f"mean   {sum(vals)//len(vals)}")
        print(f"peak   {max(vals)} ({rows[vals.index(max(vals))][0]})")
        """
        let out1 = CellRunner.runSync(language: "shell", code: genCode)
        let out2 = CellRunner.runSync(language: "python", code: statsCode, input: out1.output)

        let c1 = cell(CGRect(x: 120, y: 865, width: 300, height: 180), "shell", genCode, out1)
        let c2 = cell(CGRect(x: 470, y: 865, width: 320, height: 180), "python", statsCode, out2)

        // A rich table output cell (image/table/html outputs all render inline).
        var tableCell = Element(type: "cell", x: 840, y: 865, width: 300, height: 180, opacity: 100)
        tableCell.cellLanguage = "python"
        tableCell.text = "show_table(rows)   # rich output"
        tableCell.cellOutputType = "table"
        let tableRows: [[String]] = [["Month", "Rev"], ["Apr", "74"], ["May", "66"], ["Jun", "91"]]
        if let jd = try? JSONSerialization.data(withJSONObject: tableRows) {
            tableCell.cellOutputData = jd.base64EncodedString()
        }
        els.append(tableCell)
        let c3 = tableCell.id

        // A pass/fail test cell — green check when the assertion holds.
        let testCode = """
        # regression: revenue only grows into summer
        assert 91 == max(42, 58, 50, 74, 66, 91)
        print("peak revenue is June ✓")
        """
        let outT = CellRunner.runSync(language: "python", code: testCode)
        let ct = cell(CGRect(x: 1160, y: 865, width: 250, height: 180), "python", testCode, outT, test: true)

        link(c1, c2); link(c2, c3)
        link(c3, ct, dashed: true)
        note("generate data", 120, 1055, 300)
        note("shared kernel · $IN carries upstream output", 470, 1055, 360)
        note("rich table output", 840, 1055, 300)
        note("pass/fail test cell", 1160, 1055, 300)

        // ── Footer legend ───────────────────────────────────────────────
        note("Also on board: cross-board search (⌘F) · Obsidian vault tab · keyboard cheat sheet (?) · "
           + ".ipynb import/export · configurable master hotkeys ⌥⌘W / ⌥⌘Q",
             120, 1110, 1300, size: 13, color: "#868e96")

        return els
    }
}
