import AVFAudio
import Testing
@testable import Aufn

/// Position implies capsule and pattern; the pure mapping is what's testable
/// off-device.
struct MicPositionTests {
    @Test func casesAndDefault() {
        #expect(MicPosition.allCases == [.auto, .front, .bottom, .back])
        #expect(MicPosition.from(stored: nil) == .auto)
        #expect(MicPosition.from(stored: "sideways") == .auto)
        // Stereo was retired; a device that persisted it lands on auto.
        #expect(MicPosition.from(stored: "stereo") == .auto)
        #expect(MicPosition.from(stored: "back") == .back)
    }

    @Test(arguments: [
        (MicPosition.auto, AVAudioSession.Orientation?.none, AVAudioSession.PolarPattern?.none),
        (.front, .front, .cardioid),
        (.bottom, .bottom, .omnidirectional),
        (.back, .back, .cardioid),
    ])
    func capsuleAndPattern(position: MicPosition, orientation: AVAudioSession.Orientation?, pattern: AVAudioSession.PolarPattern?) {
        #expect(position.orientation == orientation)
        #expect(position.polarPattern == pattern)
    }

    @Test func presentationIsCompleteAndUnique() {
        let names = MicPosition.allCases.map(\.name)
        #expect(Set(names).count == names.count)
        for position in MicPosition.allCases {
            #expect(!position.name.isEmpty)
            #expect(!position.caption.isEmpty)
            #expect(!position.symbol.isEmpty)
        }
    }
}
