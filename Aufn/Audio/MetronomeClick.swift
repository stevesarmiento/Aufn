import AVFAudio

/// Renders the metronome's loop buffer: one full bar with an accented tick on
/// beat 1 and regular ticks on the rest. Pure synthesis, no engine dependency.
enum MetronomeClick {
    /// One bar at the settings' tempo and meter. The engine loops this
    /// buffer, so its exact length defines the beat grid.
    static func makeBarBuffer(settings: MetronomeSettings, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        guard sampleRate > 0, format.channelCount == 1 else { return nil }
        let bpm = settings.bpm.clamped(to: MetronomeSettings.bpmRange)
        let beatsPerBar = settings.beatsPerBar.clamped(to: MetronomeSettings.beatsPerBarRange)
        let beatFrames = Int(sampleRate * 60.0 / Double(bpm))
        let barFrames = beatsPerBar * beatFrames
        guard barFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(barFrames)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(barFrames)
        // PCM buffers aren't guaranteed zeroed; the space between ticks must
        // be true silence or the loop hisses.
        channel.update(repeating: 0, count: barFrames)

        for beat in 0..<beatsPerBar {
            let accented = beat == 0 && beatsPerBar > 1
            writeTick(
                sound: settings.sound,
                accented: accented,
                into: channel + beat * beatFrames,
                maxFrames: beatFrames,
                sampleRate: sampleRate
            )
        }
        return buffer
    }

    /// The partial bar that lets a mid-bar seek rejoin the click grid: from
    /// `phaseFrames` into the bar, silence up to the next beat boundary, then
    /// the bar's own remaining content. Scheduled once before the looping
    /// bar, so the click resumes on the next beat instead of the next bar.
    /// nil at phase 0 (the loop alone is already in phase).
    static func leadIn(bar: AVAudioPCMBuffer, phaseFrames: Int, beatFrames: Int) -> AVAudioPCMBuffer? {
        let barFrames = Int(bar.frameLength)
        guard phaseFrames > 0, phaseFrames < barFrames, beatFrames > 0,
              let source = bar.floatChannelData?[0] else { return nil }
        let nextBeat = min(barFrames, ((phaseFrames + beatFrames - 1) / beatFrames) * beatFrames)
        let length = barFrames - phaseFrames
        guard let buffer = AVAudioPCMBuffer(pcmFormat: bar.format, frameCapacity: AVAudioFrameCount(length)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(length)
        channel.update(repeating: 0, count: length)
        if nextBeat < barFrames {
            (channel + (nextBeat - phaseFrames)).update(from: source + nextBeat, count: barFrames - nextBeat)
        }
        return buffer
    }

    /// A decaying-sine tick, ≤ 30 ms — inaudible by ~15 ms, well inside even
    /// the 250 ms beat period at 240 BPM. The accent is the same sound at
    /// 1.5× pitch and higher gain.
    private static func writeTick(sound: ClickSound, accented: Bool, into channel: UnsafeMutablePointer<Float>, maxFrames: Int, sampleRate: Double) {
        let partials: [(frequency: Double, tau: Double)] = switch sound {
        case .click: [(1_000, 0.002)]
        case .beep: [(880, 0.008)]
        case .wood: [(1_700, 0.0015), (2_400, 0.0015)]
        }
        let pitchScale = accented ? 1.5 : 1.0
        // Split gain across partials so summed peaks stay below full scale.
        let gain = (accented ? 0.95 : 0.7) / Double(partials.count)
        let frames = min(maxFrames, Int(sampleRate * 0.03))
        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            var sample = 0.0
            for partial in partials {
                sample += gain * sin(2 * .pi * partial.frequency * pitchScale * t) * exp(-t / partial.tau)
            }
            channel[frame] = Float(sample)
        }
    }
}
