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
    }

    @Test func nonDefaultLevelsRoundTrip() throws {
        let track = Track(name: "T", fileName: "t.caf", isSoloed: true, sampleRate: 48_000, volume: 0.4, pan: -0.7)
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
        #expect(project.isAnyTrackSoloed)
        #expect(!project.isAudible(plain))
        #expect(project.isAudible(soloed))
    }
}
