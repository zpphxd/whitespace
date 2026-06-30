import AppKit

/// Builds a polished "Live Architecture" board: a native-shape system diagram
/// (client → API → services → datastore/cache, with a DB cylinder) annotated
/// with notes, plus a live monitoring pipeline of runnable code cells wired by
/// pipes. Saves a real `.excalidraw` (openable/runnable in Whitespace) and a
/// PNG preview. Dev harness: `--build-arch <dir>`.
enum ShowcaseBoard {
    static func buildAndSave(to dir: String) {
        let els = elements()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("Live-Architecture.excalidraw")
        DocumentStore.save(els, to: url)
        if let png = Export.png(els) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("arch.png"))
            FileHandle.standardError.write(Data("saved \(url.path)\n".utf8))
        }
    }

    static func elements() -> [Element] {
        var els: [Element] = []
        let blue = "#a5d8ff", green = "#b2f2bb", violet = "#d0bfff", pink = "#fcc2d7", orange = "#ffd8a8"

        @discardableResult
        func box(_ r: CGRect, _ text: String, _ fill: String, dia: Bool = false, rnd: Bool = true, size: Double = 16) -> String {
            var e = Element(type: dia ? "diamond" : "rectangle", x: r.minX, y: r.minY, width: r.width, height: r.height,
                            backgroundColor: fill, fillStyle: .solid, opacity: 100)
            if rnd && !dia { e.roundness = Element.Roundness(type: 3) }
            els.append(e)
            var lab = Element(type: "text", x: r.minX, y: r.minY, width: r.width, height: r.height, opacity: 100,
                              text: text, fontSize: size, textAlign: "center", verticalAlign: "middle")
            lab.containerId = e.id
            els.append(lab)
            return e.id
        }
        // A database cylinder out of two ellipses + a body rectangle.
        @discardableResult
        func cylinder(_ r: CGRect, _ text: String, _ fill: String) -> String {
            let cap = min(26.0, r.height * 0.3)
            els.append(Element(type: "ellipse", x: r.minX, y: r.maxY - cap, width: r.width, height: cap,
                               backgroundColor: fill, fillStyle: .solid, opacity: 100))           // bottom
            els.append(Element(type: "rectangle", x: r.minX, y: r.minY + cap / 2, width: r.width, height: r.height - cap,
                               backgroundColor: fill, fillStyle: .solid, opacity: 100))           // body
            let top = Element(type: "ellipse", x: r.minX, y: r.minY, width: r.width, height: cap,
                              backgroundColor: fill, fillStyle: .solid, opacity: 100)             // top
            els.append(top)
            els.append(Element(type: "text", x: r.minX, y: r.minY + cap, width: r.width, height: r.height - cap,
                               opacity: 100, text: text, fontSize: 15, textAlign: "center", verticalAlign: "middle"))
            return top.id
        }
        func note(_ text: String, _ x: Double, _ y: Double, _ w: Double = 200, size: Double = 13, color: String = "#495057") {
            els.append(Element(type: "text", x: x, y: y, width: w, height: size * 1.4, strokeColor: color,
                               opacity: 100, text: text, fontSize: size, textAlign: "left", verticalAlign: "top"))
        }
        func link(_ a: String, _ b: String, dashed: Bool = false) {
            guard let from = els.first(where: { $0.id == a }), let to = els.first(where: { $0.id == b }) else { return }
            let fe = ArrowBinding.edgePoint(of: from, toward: CGPoint(x: to.rect.midX, y: to.rect.midY))
            let te = ArrowBinding.edgePoint(of: to, toward: CGPoint(x: from.rect.midX, y: from.rect.midY))
            var ar = Element(type: "arrow", x: Double(fe.x), y: Double(fe.y),
                             strokeStyle: dashed ? .dashed : .solid, opacity: 100, endArrowhead: "arrow")
            ar.points = [[0, 0], [Double(te.x - fe.x), Double(te.y - fe.y)]]
            ar.startBindingId = a; ar.endBindingId = b
            els.append(ar)
        }
        @discardableResult
        func cell(_ r: CGRect, _ lang: String, _ code: String, _ output: String) -> String {
            var e = Element(type: "cell", x: r.minX, y: r.minY, width: r.width, height: r.height, opacity: 100)
            e.cellLanguage = lang; e.text = code; e.cellOutput = output
            els.append(e)
            return e.id
        }
        func frame(_ r: CGRect, _ label: String) {
            var f = Element(type: "frame", x: r.minX, y: r.minY, width: r.width, height: r.height, opacity: 100)
            f.text = label
            els.append(f)
        }

        // ── Title ───────────────────────────────────────────────────────
        els.append(Element(type: "text", x: 120, y: 24, width: 900, height: 40, opacity: 100,
                           text: "🏗  Live Architecture — a diagram that runs", fontSize: 30,
                           textAlign: "left", verticalAlign: "top"))

        // ── Tiers (drawn first so they sit behind the components) ───────
        frame(CGRect(x: 90, y: 110, width: 330, height: 300), "Edge")
        frame(CGRect(x: 450, y: 110, width: 360, height: 300), "Application")
        frame(CGRect(x: 850, y: 110, width: 360, height: 300), "Data")
        frame(CGRect(x: 450, y: 440, width: 500, height: 150), "Async / Workers")

        // ── Edge ────────────────────────────────────────────────────────
        let users = box(CGRect(x: 130, y: 165, width: 150, height: 62), "👥 Users", blue)
        let cdn   = box(CGRect(x: 130, y: 255, width: 150, height: 54), "CDN", blue)
        let lb    = box(CGRect(x: 130, y: 335, width: 150, height: 56), "Load Balancer", blue)

        // ── Application ─────────────────────────────────────────────────
        let api   = box(CGRect(x: 470, y: 200, width: 160, height: 96), "API Gateway", violet, dia: true)
        let auth  = box(CGRect(x: 660, y: 150, width: 140, height: 58), "Auth", green)
        let ord   = box(CGRect(x: 660, y: 232, width: 140, height: 58), "Orders", green)
        let pay   = box(CGRect(x: 660, y: 314, width: 140, height: 58), "Payments", green)

        // ── Data ────────────────────────────────────────────────────────
        let pg    = cylinder(CGRect(x: 880, y: 150, width: 130, height: 108), "Postgres", pink)
        let redis = box(CGRect(x: 1040, y: 165, width: 130, height: 60), "Redis", orange)
        let s3    = cylinder(CGRect(x: 880, y: 290, width: 130, height: 100), "S3 / Blob", blue)

        // ── Async / external ────────────────────────────────────────────
        let queue  = box(CGRect(x: 480, y: 480, width: 130, height: 58), "Queue", orange)
        let worker = box(CGRect(x: 650, y: 480, width: 130, height: 58), "Worker", orange)
        let email  = box(CGRect(x: 820, y: 480, width: 120, height: 58), "✉ Email API", "#e9ecef")

        // ── Wiring ──────────────────────────────────────────────────────
        link(users, lb); link(users, cdn, dashed: true); link(lb, api)
        link(api, auth); link(api, ord); link(api, pay)
        link(auth, pg); link(ord, pg); link(pay, pg)
        link(ord, redis, dashed: true)
        link(ord, queue); link(queue, worker); link(worker, email, dashed: true); link(worker, s3)

        note("Users · CDN · TLS", 110, 392, 200)
        note("Stateless · scales out", 470, 392, 220)
        note("Source of truth · cache · blobs", 850, 392, 280)
        note("Background jobs, email, webhooks", 460, 562, 320)

        // ── Live monitoring pipeline (runnable cells joined by pipes) ────
        frame(CGRect(x: 90, y: 630, width: 1180, height: 330), "Observability — live")
        els.append(Element(type: "text", x: 120, y: 648, width: 760, height: 28, strokeColor: "#0b7285",
                           opacity: 100, text: "▶ Live monitoring — runs on your machine (⌘⇧↵)", fontSize: 18,
                           textAlign: "left", verticalAlign: "top"))

        let genCode = """
        # synth request log: "latency_ms status"
        for i in $(seq 1 12); do
          s=200; [ $((RANDOM%10)) -eq 0 ] && s=500
          echo "$((RANDOM%480+40)) $s"
        done
        """
        let statsCode = """
        import sys
        rows = [l.split() for l in sys.stdin if l.strip()]
        lat = sorted(int(r[0]) for r in rows)
        pct = lambda p: lat[min(len(lat)-1, int(len(lat)*p))]
        errs = sum(1 for r in rows if r[1] != "200")
        print(f"requests {len(rows)}")
        print(f"p50 {pct(.5)}ms   p95 {pct(.95)}ms")
        print(f"errors {errs} ({errs/len(rows)*100:.0f}%)")
        """
        let alertCode = """
        echo "── health check ──"
        echo "$IN" | grep -E "p50|errors"
        echo "$IN" | grep -q "errors 0" \\
          && echo "✅ healthy" \\
          || echo "⚠️  degraded — page on-call"
        """

        let out1 = CellRunner.runSync(language: "shell", code: genCode)
        let out2 = CellRunner.runSync(language: "python", code: statsCode, input: out1.output)
        let out3 = CellRunner.runSync(language: "shell", code: alertCode, input: out2.output)

        let c1 = cell(CGRect(x: 120, y: 690, width: 300, height: 190), "shell", genCode, out1.output)
        let c2 = cell(CGRect(x: 470, y: 690, width: 330, height: 190), "python", statsCode, out2.output)
        let c3 = cell(CGRect(x: 850, y: 690, width: 300, height: 220), "shell", alertCode, out3.output)
        let oncall = box(CGRect(x: 1180, y: 740, width: 70, height: 110), "📟 On-call", pink)
        link(c1, c2); link(c2, c3); link(c3, oncall, dashed: true)

        note("generate traffic", 120, 890, 200)
        note("p50 / p95 / error-rate", 470, 890, 260)
        note("decide health from $IN", 850, 920, 260)

        // Shift everything right so the floating tool palette (top-left, ~400pt
        // wide) never covers the diagram when the board opens at the origin.
        let ox = 360.0
        for i in els.indices { els[i].x += ox }
        return els
    }
}
