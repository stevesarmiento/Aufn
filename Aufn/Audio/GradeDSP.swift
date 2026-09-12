import Accelerate
import Foundation

/// The primitives a grade is built from. All zero-latency, all in place, all
/// plain Swift so they can run inside the input tap without touching the
/// engine graph. Coefficients are derived in Double and run in Float.

// MARK: - Biquad

/// Normalized (a0 = 1) second-order section, RBJ cookbook.
struct BiquadCoefficients: Equatable {
    var b0: Float
    var b1: Float
    var b2: Float
    var a1: Float
    var a2: Float

    /// nil for a 0 dB shelf or peak: skipping the section is a bit-exact
    /// bypass, which running unity coefficients would not be.
    static func make(_ band: EQBand, sampleRate: Double) -> BiquadCoefficients? {
        guard !band.isIdentity else { return nil }
        let A = pow(10, band.gainDB / 40)
        let w0 = 2 * Double.pi * band.frequency / sampleRate
        let c = cos(w0)
        let alpha = sin(w0) / (2 * band.q)
        let s = A.squareRoot()

        let b0, b1, b2, a0, a1, a2: Double
        switch band.kind {
        case .lowShelf:
            b0 = A * ((A + 1) - (A - 1) * c + 2 * s * alpha)
            b1 = 2 * A * ((A - 1) - (A + 1) * c)
            b2 = A * ((A + 1) - (A - 1) * c - 2 * s * alpha)
            a0 = (A + 1) + (A - 1) * c + 2 * s * alpha
            a1 = -2 * ((A - 1) + (A + 1) * c)
            a2 = (A + 1) + (A - 1) * c - 2 * s * alpha
        case .highShelf:
            b0 = A * ((A + 1) + (A - 1) * c + 2 * s * alpha)
            b1 = -2 * A * ((A - 1) + (A + 1) * c)
            b2 = A * ((A + 1) + (A - 1) * c - 2 * s * alpha)
            a0 = (A + 1) - (A - 1) * c + 2 * s * alpha
            a1 = 2 * ((A - 1) - (A + 1) * c)
            a2 = (A + 1) - (A - 1) * c - 2 * s * alpha
        case .peak:
            b0 = 1 + alpha * A
            b1 = -2 * c
            b2 = 1 - alpha * A
            a0 = 1 + alpha / A
            a1 = -2 * c
            a2 = 1 - alpha / A
        case .highPass:
            b0 = (1 + c) / 2
            b1 = -(1 + c)
            b2 = (1 + c) / 2
            a0 = 1 + alpha
            a1 = -2 * c
            a2 = 1 - alpha
        }
        return BiquadCoefficients(
            b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b2 / a0),
            a1: Float(a1 / a0), a2: Float(a2 / a0)
        )
    }

    /// |H| at DC, from the normalized coefficients.
    var dcGain: Double {
        Double(b0 + b1 + b2) / Double(1 + a1 + a2)
    }
}

/// One channel of biquad state (transposed direct form II).
struct BiquadState {
    let coefficients: BiquadCoefficients
    private var s1: Float = 0
    private var s2: Float = 0

    init(coefficients: BiquadCoefficients) {
        self.coefficients = coefficients
    }

    mutating func process(_ samples: UnsafeMutablePointer<Float>, count: Int) {
        let (b0, b1, b2, a1, a2) = (coefficients.b0, coefficients.b1, coefficients.b2, coefficients.a1, coefficients.a2)
        var s1 = self.s1
        var s2 = self.s2
        for i in 0..<count {
            let x = samples[i]
            let y = b0 * x + s1
            s1 = b1 * x - a1 * y + s2
            s2 = b2 * x - a2 * y
            samples[i] = y
        }
        self.s1 = s1
        self.s2 = s2
    }
}

// MARK: - Compressor

/// Feed-forward compressor with a soft knee, computed in dB with a branching
/// one-pole smoother on the gain reduction (Giannoulis/Massberg/Reiss). One
/// detector across all channels — max(|L|, |R|) per frame — so a stereo
/// image never wanders. Below the knee the log is skipped entirely.
final class Compressor {
    private let attackCoefficient: Float
    private let releaseCoefficient: Float
    private let slope: Float
    private let thresholdDB: Float
    private let kneeDB: Float
    private let kneeStartLinear: Float
    private let makeupDB: Float
    /// Current gain reduction in dB, shared by every channel.
    private var reductionDB: Float = 0

    private static let dBPerLog2: Float = 6.0206
    private static let log2PerDB: Float = 1 / 6.0206

    init(settings: CompressorSettings, sampleRate: Double) {
        func coefficient(ms: Float) -> Float {
            ms > 0 ? Float(exp(-1 / (Double(ms) / 1000 * sampleRate))) : 0
        }
        attackCoefficient = coefficient(ms: settings.attackMs)
        releaseCoefficient = coefficient(ms: settings.releaseMs)
        slope = 1 - 1 / settings.ratio
        thresholdDB = settings.thresholdDB
        kneeDB = settings.kneeDB
        kneeStartLinear = pow(10, (settings.thresholdDB - settings.kneeDB / 2) / 20)
        makeupDB = settings.makeupDB
    }

    func process(channels: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int, frames: Int) {
        var reduction = reductionDB
        for frame in 0..<frames {
            var peak: Float = 0
            for channel in 0..<channelCount {
                peak = max(peak, abs(channels[channel][frame]))
            }
            var target: Float = 0
            if peak >= kneeStartLinear {
                let levelDB = Self.dBPerLog2 * log2(peak)
                let over = levelDB - thresholdDB
                if kneeDB > 0, over <= kneeDB / 2 {
                    let inKnee = over + kneeDB / 2
                    target = slope * inKnee * inKnee / (2 * kneeDB)
                } else {
                    target = slope * over
                }
            }
            let coefficient = target > reduction ? attackCoefficient : releaseCoefficient
            reduction = coefficient * reduction + (1 - coefficient) * target
            let gain = exp2((makeupDB - reduction) * Self.log2PerDB)
            for channel in 0..<channelCount {
                channels[channel][frame] *= gain
            }
        }
        reductionDB = reduction
    }
}

// MARK: - Soft clip

enum SoftClip {
    /// y = tanh(d·x) / d: unity gain for small signals, peaks rounded off
    /// and bounded at 1/d.
    static func process(_ samples: UnsafeMutablePointer<Float>, count: Int, drive: Float) {
        var count32 = Int32(count)
        var scale = drive
        var inverse = 1 / drive
        vDSP_vsmul(samples, 1, &scale, samples, 1, vDSP_Length(count))
        vvtanhf(samples, samples, &count32)
        vDSP_vsmul(samples, 1, &inverse, samples, 1, vDSP_Length(count))
    }
}
