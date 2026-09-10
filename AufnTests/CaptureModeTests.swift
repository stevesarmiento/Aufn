import AVFAudio
import Testing
@testable import Aufn

/// The wheel is processing-only: two stops, and the retired "voice" value a
/// device may still have persisted degrades to raw.
struct CaptureModeTests {
    @Test func onlyRawAndTapeRemain() {
        #expect(CaptureMode.allCases == [.raw, .standard])
        #expect(CaptureMode(rawValue: "voice") == nil)
    }

    @Test func storedValuesFallBackToRaw() {
        #expect(CaptureMode.from(stored: "voice") == .raw)
        #expect(CaptureMode.from(stored: nil) == .raw)
        #expect(CaptureMode.from(stored: "garbage") == .raw)
        #expect(CaptureMode.from(stored: "standard") == .standard)
    }

    @Test func sessionModes() {
        #expect(CaptureMode.raw.sessionMode == .measurement)
        #expect(CaptureMode.standard.sessionMode == .default)
    }
}
