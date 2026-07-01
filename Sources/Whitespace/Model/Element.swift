import Foundation

/// An Excalidraw element. A single flat struct (rather than a class hierarchy)
/// mirrors the `.excalidraw` JSON shape and round-trips cleanly; type-specific
/// fields are optional and only meaningful for the matching `type`.
struct Element: Codable, Identifiable, Equatable {
    var id: String
    var type: String

    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var angle: Double

    var strokeColor: String
    var backgroundColor: String
    var fillStyle: FillStyle
    var strokeWidth: Double
    var strokeStyle: StrokeStyle
    var roughness: Double
    var opacity: Double

    var seed: Int
    var version: Int
    var versionNonce: Int
    var isDeleted: Bool
    var groupIds: [String]
    var frameId: String?
    var roundness: Roundness?
    var boundElements: [BoundElement]?
    var updated: Double
    var link: String?
    var locked: Bool
    var index: String?

    // Linear (line/arrow) + freedraw
    var points: [[Double]]?
    var pressures: [Double]?
    var lastCommittedPoint: [Double]?
    /// Freedraw: whether width varies with drawing speed. nil/true = variable
    /// (perfect-freehand), false = uniform thickness.
    var simulatePressure: Bool?
    var startArrowhead: String?
    var endArrowhead: String?
    var elbowed: Bool = false
    // Simple element-id bindings so arrows link shapes and follow them.
    var startBindingId: String?
    var endBindingId: String?
    // Normalized [u,v] anchor on the bound shape's box (Excalidraw's fixedPoint):
    // the arrow welds to this spot and tracks it through moves/resizes. Nil →
    // fall back to the center-ray edge projection.
    var startBindingPoint: [Double]?
    var endBindingPoint: [Double]?

    // Text
    var text: String?
    var fontSize: Double?
    var fontFamily: Int?
    var textAlign: String?
    var verticalAlign: String?
    var containerId: String?
    var originalText: String?
    var lineHeight: Double?

    // Live cells (executable code / data). `text` holds the source; these add
    // the language and the last captured output. Whitespace extension to the
    // Excalidraw schema — ignored by other tools, tolerated on decode.
    var cellLanguage: String?
    var cellOutput: String?
    var cellExecCount: Int?   // Jupyter-style [n] run counter
    var cellFailed: Bool?     // last run raised / exited non-zero

    struct Roundness: Codable, Equatable {
        var type: Int
        var value: Double?
    }

    struct BoundElement: Codable, Equatable {
        var id: String
        var type: String
    }

    // Defaults so missing JSON keys decode cleanly.
    init(
        id: String = UUID().uuidString,
        type: String,
        x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0,
        angle: Double = 0,
        strokeColor: String = "#1e1e1e",
        backgroundColor: String = "transparent",
        fillStyle: FillStyle = .solid,
        strokeWidth: Double = 2,
        strokeStyle: StrokeStyle = .solid,
        roughness: Double = 1,
        opacity: Double = 100,
        seed: Int = Int.random(in: 1...2_000_000_000),
        version: Int = 1,
        versionNonce: Int = Int.random(in: 1...2_000_000_000),
        isDeleted: Bool = false,
        groupIds: [String] = [],
        frameId: String? = nil,
        roundness: Roundness? = nil,
        boundElements: [BoundElement]? = nil,
        updated: Double = 0,
        link: String? = nil,
        locked: Bool = false,
        index: String? = nil,
        points: [[Double]]? = nil,
        pressures: [Double]? = nil,
        lastCommittedPoint: [Double]? = nil,
        simulatePressure: Bool? = nil,
        startArrowhead: String? = nil,
        endArrowhead: String? = nil,
        elbowed: Bool = false,
        startBindingId: String? = nil,
        endBindingId: String? = nil,
        startBindingPoint: [Double]? = nil,
        endBindingPoint: [Double]? = nil,
        text: String? = nil,
        fontSize: Double? = nil,
        fontFamily: Int? = nil,
        textAlign: String? = nil,
        verticalAlign: String? = nil,
        containerId: String? = nil,
        originalText: String? = nil,
        lineHeight: Double? = nil,
        cellLanguage: String? = nil,
        cellOutput: String? = nil,
        cellExecCount: Int? = nil,
        cellFailed: Bool? = nil
    ) {
        self.id = id; self.type = type
        self.x = x; self.y = y; self.width = width; self.height = height; self.angle = angle
        self.strokeColor = strokeColor; self.backgroundColor = backgroundColor
        self.fillStyle = fillStyle; self.strokeWidth = strokeWidth; self.strokeStyle = strokeStyle
        self.roughness = roughness; self.opacity = opacity
        self.seed = seed; self.version = version; self.versionNonce = versionNonce
        self.isDeleted = isDeleted; self.groupIds = groupIds; self.frameId = frameId
        self.roundness = roundness; self.boundElements = boundElements; self.updated = updated
        self.link = link; self.locked = locked; self.index = index
        self.points = points; self.pressures = pressures; self.lastCommittedPoint = lastCommittedPoint
        self.simulatePressure = simulatePressure
        self.startArrowhead = startArrowhead; self.endArrowhead = endArrowhead
        self.elbowed = elbowed
        self.startBindingId = startBindingId; self.endBindingId = endBindingId
        self.startBindingPoint = startBindingPoint; self.endBindingPoint = endBindingPoint
        self.text = text; self.fontSize = fontSize; self.fontFamily = fontFamily
        self.textAlign = textAlign; self.verticalAlign = verticalAlign
        self.containerId = containerId; self.originalText = originalText; self.lineHeight = lineHeight
        self.cellLanguage = cellLanguage; self.cellOutput = cellOutput
        self.cellExecCount = cellExecCount; self.cellFailed = cellFailed
    }

    // Lenient decoding: tolerate any subset of keys (files from other tools vary).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: k)) .flatMap { $0 } ?? fallback
        }
        id = d(.id, UUID().uuidString)
        type = d(.type, "rectangle")
        x = d(.x, 0); y = d(.y, 0); width = d(.width, 0); height = d(.height, 0)
        angle = d(.angle, 0)
        strokeColor = d(.strokeColor, "#1e1e1e")
        backgroundColor = d(.backgroundColor, "transparent")
        fillStyle = (try? c.decodeIfPresent(FillStyle.self, forKey: .fillStyle)) .flatMap { $0 } ?? .solid
        strokeWidth = d(.strokeWidth, 2)
        strokeStyle = (try? c.decodeIfPresent(StrokeStyle.self, forKey: .strokeStyle)) .flatMap { $0 } ?? .solid
        roughness = d(.roughness, 1)
        opacity = d(.opacity, 100)
        seed = d(.seed, Int.random(in: 1...2_000_000_000))
        version = d(.version, 1)
        versionNonce = d(.versionNonce, Int.random(in: 1...2_000_000_000))
        isDeleted = d(.isDeleted, false)
        groupIds = d(.groupIds, [])
        frameId = try? c.decodeIfPresent(String.self, forKey: .frameId)
        roundness = try? c.decodeIfPresent(Roundness.self, forKey: .roundness)
        boundElements = try? c.decodeIfPresent([BoundElement].self, forKey: .boundElements)
        updated = d(.updated, 0)
        link = try? c.decodeIfPresent(String.self, forKey: .link)
        locked = d(.locked, false)
        index = try? c.decodeIfPresent(String.self, forKey: .index)
        points = try? c.decodeIfPresent([[Double]].self, forKey: .points)
        pressures = try? c.decodeIfPresent([Double].self, forKey: .pressures)
        lastCommittedPoint = try? c.decodeIfPresent([Double].self, forKey: .lastCommittedPoint)
        simulatePressure = try? c.decodeIfPresent(Bool.self, forKey: .simulatePressure)
        startArrowhead = try? c.decodeIfPresent(String.self, forKey: .startArrowhead)
        endArrowhead = try? c.decodeIfPresent(String.self, forKey: .endArrowhead)
        elbowed = d(.elbowed, false)
        startBindingId = try? c.decodeIfPresent(String.self, forKey: .startBindingId)
        endBindingId = try? c.decodeIfPresent(String.self, forKey: .endBindingId)
        startBindingPoint = try? c.decodeIfPresent([Double].self, forKey: .startBindingPoint)
        endBindingPoint = try? c.decodeIfPresent([Double].self, forKey: .endBindingPoint)
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        fontSize = try? c.decodeIfPresent(Double.self, forKey: .fontSize)
        fontFamily = try? c.decodeIfPresent(Int.self, forKey: .fontFamily)
        textAlign = try? c.decodeIfPresent(String.self, forKey: .textAlign)
        verticalAlign = try? c.decodeIfPresent(String.self, forKey: .verticalAlign)
        containerId = try? c.decodeIfPresent(String.self, forKey: .containerId)
        originalText = try? c.decodeIfPresent(String.self, forKey: .originalText)
        lineHeight = try? c.decodeIfPresent(Double.self, forKey: .lineHeight)
        cellLanguage = try? c.decodeIfPresent(String.self, forKey: .cellLanguage)
        cellOutput = try? c.decodeIfPresent(String.self, forKey: .cellOutput)
        cellExecCount = try? c.decodeIfPresent(Int.self, forKey: .cellExecCount)
        cellFailed = try? c.decodeIfPresent(Bool.self, forKey: .cellFailed)
    }
}
