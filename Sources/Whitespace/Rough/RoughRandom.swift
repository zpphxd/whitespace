import Foundation

/// Park–Miller minimal-standard PRNG, bit-for-bit matching rough.js's `Random`
/// class so a given `seed` reproduces the same hand-drawn jitter every render.
///
/// rough.js: `(2**31 - 1) & (this.seed = Math.imul(48271, this.seed))) / 2**31`
final class RoughRandom {
    private var seed: Int32

    init(seed: Int) {
        self.seed = Int32(truncatingIfNeeded: seed)
    }

    /// Returns a value in [0, 1), advancing the generator.
    func next() -> Double {
        // Math.imul(48271, seed): 32-bit signed multiply, low 32 bits.
        seed = Int32(truncatingIfNeeded: 48271 &* Int64(seed))
        // (2^31 - 1) & seed → non-negative 31-bit value.
        let bits = UInt32(bitPattern: seed) & 0x7fff_ffff
        return Double(bits) / 2_147_483_648.0 // 2^31
    }
}
