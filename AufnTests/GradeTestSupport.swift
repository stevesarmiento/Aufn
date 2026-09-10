import AVFAudio
import Accelerate
import Foundation
import Testing
@testable import Aufn

/// Deterministic test signals and measurements for the grade DSP. Everything
/// is float32 non-interleaved at 48 kHz, the same shape the input tap hands
/// the processor.
enum GradeTestSupport {
    static let sampleRate: Double = 48_000

    static func makeBuffer(channels: Int, frames: Int) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels)))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)))
        buffer.frameLength = AVAudioFrameCount(frames)
        return buffer
    }

    static func fill(_ buffer: AVAudioPCMBuffer, channel: Int, _ sample: (Int) -> Float) {
        let data = buffer.floatChannelData![channel]
        for frame in 0..<Int(buffer.frameLength) {
            data[frame] = sample(frame)
        }
    }

    /// Constant level on every channel.
    static func dc(_ value: Float, seconds: Double, channels: Int = 1) throws -> AVAudioPCMBuffer {
        let buffer = try makeBuffer(channels: channels, frames: Int(seconds * sampleRate))
        for channel in 0..<channels { fill(buffer, channel: channel) { _ in value } }
        return buffer
    }

    static func sine(frequency: Double, amplitude: Float, seconds: Double, channels: Int = 1) throws -> AVAudioPCMBuffer {
        let buffer = try makeBuffer(channels: channels, frames: Int(seconds * sampleRate))
        for channel in 0..<channels {
            fill(buffer, channel: channel) { frame in
                amplitude * Float(sin(2 * Double.pi * frequency * Double(frame) / sampleRate))
            }
        }
        return buffer
    }

    /// Alternating ±amplitude: a full-scale-frequency tone at fs/2.
    static func nyquist(amplitude: Float, seconds: Double) throws -> AVAudioPCMBuffer {
        let buffer = try makeBuffer(channels: 1, frames: Int(seconds * sampleRate))
        fill(buffer, channel: 0) { frame in frame % 2 == 0 ? amplitude : -amplitude }
        return buffer
    }

    /// Seeded LCG noise, uniform in ±peak, independent per channel.
    static func noise(seed: UInt32, peak: Float, seconds: Double, channels: Int = 1) throws -> AVAudioPCMBuffer {
        let buffer = try makeBuffer(channels: channels, frames: Int(seconds * sampleRate))
        var state = seed
        for channel in 0..<channels {
            fill(buffer, channel: channel) { _ in
                state = state &* 1_664_525 &+ 1_013_904_223
                return (Float(state) / Float(UInt32.max) * 2 - 1) * peak
            }
        }
        return buffer
    }

    static func samples(of buffer: AVAudioPCMBuffer, channel: Int = 0) -> [Float] {
        Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength)))
    }

    static func copy(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let channels = Int(buffer.format.channelCount)
        let result = try makeBuffer(channels: channels, frames: Int(buffer.frameLength))
        for channel in 0..<channels {
            result.floatChannelData![channel].update(from: buffer.floatChannelData![channel], count: Int(buffer.frameLength))
        }
        return result
    }

    static func rms(_ buffer: AVAudioPCMBuffer, channel: Int = 0, from start: Int, count: Int) -> Float {
        var value: Float = 0
        vDSP_rmsqv(buffer.floatChannelData![channel] + start, 1, &value, vDSP_Length(count))
        return value
    }

    static func peak(_ buffer: AVAudioPCMBuffer, channel: Int = 0) -> Float {
        var value: Float = 0
        vDSP_maxmgv(buffer.floatChannelData![channel], 1, &value, vDSP_Length(buffer.frameLength))
        return value
    }

    static func dB(_ ratio: Float) -> Float {
        20 * log10(ratio)
    }

    /// Steady-state gain of `buffer` relative to a sine of `amplitude`,
    /// measured over whole cycles after `discard` seconds.
    static func steadyGainDB(_ buffer: AVAudioPCMBuffer, channel: Int = 0, frequency: Double, amplitude: Float, discard: Double, cycles: Int = 100) -> Float {
        let start = Int(discard * sampleRate)
        let count = Int(sampleRate / frequency) * cycles
        precondition(start + count <= Int(buffer.frameLength), "test signal too short")
        return dB(rms(buffer, channel: channel, from: start, count: count) / (amplitude / Float(2).squareRoot()))
    }

    /// Runs `buffer` through `processor` as a sequence of fresh buffers whose
    /// lengths cycle through `lengths`, returning the concatenated output.
    static func processInChunks(_ processor: GradeProcessor, _ buffer: AVAudioPCMBuffer, lengths: [Int]) throws -> AVAudioPCMBuffer {
        let channels = Int(buffer.format.channelCount)
        let total = Int(buffer.frameLength)
        let output = try makeBuffer(channels: channels, frames: total)
        var offset = 0
        var index = 0
        while offset < total {
            let length = min(lengths[index % lengths.count], total - offset)
            let chunk = try makeBuffer(channels: channels, frames: length)
            for channel in 0..<channels {
                chunk.floatChannelData![channel].update(from: buffer.floatChannelData![channel] + offset, count: length)
            }
            processor.process(chunk)
            for channel in 0..<channels {
                (output.floatChannelData![channel] + offset).update(from: chunk.floatChannelData![channel], count: length)
            }
            offset += length
            index += 1
        }
        return output
    }
}
