import Foundation
import Testing
@testable import Aufn

/// Projects written before volume/pan/masterVolume existed must keep decoding
/// (ProjectStore uses `try?`, so a decode failure silently drops the project).
struct ModelCodableTests {
    private let legacyProjectJSON = """
    {
      "createdAt" : "2026-09-09T01:16:33Z",
      "id" : "061D7BB3-04B3-44A1-A7FD-FB54DF100DCB",
      "name" : "Legacy Project",
      "sampleRate" : 48000,
      "tracks" : [
        {
          "createdAt" : "2026-09-09T01:16:43Z",
          "durationSeconds" : 5.19,
          "fileName" : "a.caf",
          "id" : "DF71E210-8CBD-42CA-A009-2AC47185162B",
          "isMuted" : false,
          "latencyOffsetSamples" : 10,
          "name" : "Track 1",
          "sampleRate" : 48000
        }
      ]
    }
    """

    @Test func legacyProjectDecodesWithDefaultLevels() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(Project.self, from: Data(legacyProjectJSON.utf8))
        #expect(project.name == "Legacy Project")
        #expect(project.masterVolume == 1)
        #expect(project.tracks.count == 1)
        #expect(project.tracks[0].volume == 1)
        #expect(project.tracks[0].pan == 0)
        #expect(project.tracks[0].isSoloed == false)
        #expect(project.tracks[0].channelCount == 1)
        #expect(project.metronome == nil)
    }

    @Test func nonDefaultLevelsRoundTrip() throws {
        let track = Track(name: "T", fileName: "t.caf", isSoloed: true, sampleRate: 48_000, channelCount: 2, volume: 0.4, pan: -0.7)
        let project = Project(name: "P", sampleRate: 48_000, tracks: [track], masterVolume: 0.8)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Project.self, from: encoder.encode(project))
        #expect(decoded.masterVolume == 0.8)
        #expect(decoded.tracks[0].volume == 0.4)
        #expect(decoded.tracks[0].pan == -0.7)
        #expect(decoded.tracks[0].isSoloed == true)
        #expect(decoded.tracks[0].channelCount == 2)
    }

    @Test func mixRulesAudibility() {
        let plain = Track(name: "A", fileName: "a.caf", sampleRate: 48_000)
        let muted = Track(name: "B", fileName: "b.caf", isMuted: true, sampleRate: 48_000)
        let soloed = Track(name: "C", fileName: "c.caf", isSoloed: true, sampleRate: 48_000, volume: 0.5)
        let mutedAndSoloed = Track(name: "D", fileName: "d.caf", isMuted: true, isSoloed: true, sampleRate: 48_000)

        // No solo active: non-muted tracks are audible.
        #expect(MixRules.isAudible(plain, anySoloed: false))
        #expect(!MixRules.isAudible(muted, anySoloed: false))

        // Solo active: only soloed tracks play, mute beats solo.
        #expect(!MixRules.isAudible(plain, anySoloed: true))
        #expect(MixRules.isAudible(soloed, anySoloed: true))
        #expect(!MixRules.isAudible(mutedAndSoloed, anySoloed: true))

        #expect(MixRules.effectiveVolume(for: soloed, anySoloed: true) == 0.5)
        #expect(MixRules.effectiveVolume(for: plain, anySoloed: true) == 0)

        let project = Project(name: "P", tracks: [plain, soloed])
        #expect(project.isAnySoloed)
        #expect(!project.isAudible(plain))
        #expect(project.isAudible(soloed))
    }

    @Test func metronomeRoundTrip() throws {
        let metronome = MetronomeSettings(bpm: 96, beatsPerBar: 3, sound: .wood, countInBars: 2, volume: 0.5, isSoloed: true)
        let project = Project(name: "P", metronome: metronome)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Project.self, from: encoder.encode(project))
        #expect(decoded.metronome == metronome)

        let plain = Project(name: "Q")
        let decodedPlain = try decoder.decode(Project.self, from: encoder.encode(plain))
        #expect(decodedPlain.metronome == nil)
    }

    @Test func metronomeDecodesWithMissingAndUnknownFields() throws {
        // Partial/forward-schema JSON must fill defaults, not throw — a throw
        // would silently drop the whole project via ProjectStore's try?.
        let json = """
        { "bpm": 100, "sound": "cowbell" }
        """
        let settings = try JSONDecoder().decode(MetronomeSettings.self, from: Data(json.utf8))
        #expect(settings.bpm == 100)
        #expect(settings.beatsPerBar == 4)
        #expect(settings.sound == .click)
        #expect(settings.countInBars == 0)
        #expect(settings.volume == 0.8)
        #expect(settings.isMuted == false)
        #expect(settings.isSoloed == false)

        let outOfRange = try JSONDecoder().decode(MetronomeSettings.self, from: Data("{ \"bpm\": 999, \"beatsPerBar\": 0, \"countInBars\": 9 }".utf8))
        #expect(outOfRange.bpm == 240)
        #expect(outOfRange.beatsPerBar == 1)
        #expect(outOfRange.countInBars == 2)
    }

    @Test func mixRulesWithMetronome() {
        let plain = Track(name: "A", fileName: "a.caf", sampleRate: 48_000)

        // Metronome soloed: it plays, plain tracks don't.
        let metronomeSoloed = Project(name: "P", tracks: [plain], metronome: MetronomeSettings(volume: 0.6, isSoloed: true))
        #expect(metronomeSoloed.isAnySoloed)
        #expect(!metronomeSoloed.isAudible(plain))
        #expect(metronomeSoloed.isMetronomeAudible)
        #expect(metronomeSoloed.metronomeEffectiveVolume == 0.6)

        // A track soloed: the plain metronome goes silent.
        var soloedTrack = plain
        soloedTrack.isSoloed = true
        let trackSoloed = Project(name: "P", tracks: [soloedTrack], metronome: MetronomeSettings())
        #expect(!trackSoloed.isMetronomeAudible)
        #expect(trackSoloed.metronomeEffectiveVolume == 0)

        // Mute beats solo on the metronome too, but its solo still gates others.
        let mutedAndSoloed = Project(name: "P", tracks: [plain], metronome: MetronomeSettings(isMuted: true, isSoloed: true))
        #expect(mutedAndSoloed.isAnySoloed)
        #expect(!mutedAndSoloed.isMetronomeAudible)
        #expect(!mutedAndSoloed.isAudible(plain))

        // No metronome: nothing changes.
        let none = Project(name: "P", tracks: [plain])
        #expect(!none.isAnySoloed)
        #expect(none.metronomeEffectiveVolume == 0)
    }
}
