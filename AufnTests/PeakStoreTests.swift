import Foundation
import Testing
@testable import Aufn

struct PeakStoreTests {
    @Test func writePeaksRoundTripsThroughLoadPeaks() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "PeakStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "take.peaks")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let peaks: [Float] = [0, 0.25, 0.5, 1, 0.125]
        try PeakStore.writePeaks(peaks, to: url)
        #expect(PeakStore.loadPeaks(from: url) == peaks)
    }

    @Test func emptyCacheLoadsAsNil() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).peaks")
        try PeakStore.writePeaks([], to: url)
        #expect(PeakStore.loadPeaks(from: url) == nil)
        try? FileManager.default.removeItem(at: url)
    }
}
