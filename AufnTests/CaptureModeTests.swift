import AVFAudio
import Testing
@testable import Aufn

/// The wheel is a printed grade: RAW plus three of ours. The retired values a
/// device may still have persisted degrade sensibly — "standard" (the old
/// Apple-processed TAPE) becomes our tape, anything else becomes raw.
struct CaptureModeTests {
    @Test func rawAndThreeGrades() {
        #expect(CaptureMode.allCases == [.raw, .tape, .warm, .glue])
        #expect(CaptureMode(rawValue: "voice") == nil)
        #expect(CaptureMode(rawValue: "standard") == nil)
    }

    @Test func storedValuesDegrade() {
        #expect(CaptureMode.from(stored: "standard") == .tape)
        #expect(CaptureMode.from(stored: "voice") == .raw)
        #expect(CaptureMode.from(stored: nil) == .raw)
        #expect(CaptureMode.from(stored: "garbage") == .raw)
        #expect(CaptureMode.from(stored: "warm") == .warm)
    }

    @Test func onlyRawIsIdentity() {
        for mode in CaptureMode.allCases {
            #expect(mode.grade.isIdentity == (mode == .raw))
        }
    }

    @Test func presentationIsCompleteAndUnique() {
        let labels = CaptureMode.allCases.map(\.label)
        #expect(Set(labels).count == labels.count)
        let badges = CaptureMode.allCases.compactMap(\.badgeLetter)
        #expect(Set(badges).count == badges.count)
        for mode in CaptureMode.allCases {
            #expect(!mode.label.isEmpty)
            #expect(!mode.caption.isEmpty)
            #expect((mode.badgeLetter == nil) == (mode == .raw))
            #expect(mode.badgeLetter.map { $0.count == 1 && mode.label.hasPrefix($0) } ?? true)
        }
    }
}
