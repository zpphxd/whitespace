import Foundation

/// rough.js drawing options. Defaults mirror rough.js; Excalidraw overrides a
/// handful per element (seed, roughness, strokeWidth, fillWeight, hachureGap,
/// disableMultiStroke for dashed/dotted, preserveVertices).
struct RoughOptions {
    var maxRandomnessOffset: Double = 2
    var roughness: Double = 1
    var bowing: Double = 1
    var strokeWidth: Double = 1
    var curveTightness: Double = 0
    var curveFitting: Double = 0.95
    var curveStepCount: Double = 9
    var hachureAngle: Double = -41
    var hachureGap: Double = -1
    var fillWeight: Double = -1
    var disableMultiStroke: Bool = false
    var disableMultiStrokeFill: Bool = false
    var preserveVertices: Bool = false
    var seed: Int = 0
}
