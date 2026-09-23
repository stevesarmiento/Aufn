import AVFAudio
import SwiftUI

/// Fixtures for Xcode previews. The store is disk-backed in the preview
/// sandbox and seeded with synthetic peaks caches, so track rows and the
/// transport tape render real waveforms without any recorded audio.
enum PreviewData {
    /// Synthetic peak bins shaped like a take: bursts of signal over a
    /// low noise floor. ~20 ms per bin, matching PeakStore.
    static func peaks(bins: Int = 900, seed: Double = 0.09) -> [Float] {
        (0..<bins).map { index in
            abs(sin(Double(index) * seed)) > 0.3 ? Float(abs(sin(Double(index) * 0.21))) : 0.05
        }
    }

    /// Fresh store in the preview sandbox: "Demo Song" with three tracks
    /// (one muted) plus an empty "Sketch". Pass `seeded: false` for the
    /// no-projects empty state.
    @MainActor
    static func store(seeded: Bool = true) -> ProjectStore {
        try? FileManager.default.removeItem(at: URL.documentsDirectory.appending(path: "Projects"))
        let store = ProjectStore()
        guard seeded else { return store }
        _ = try? store.createProject(named: "Sketch")
        guard let project = try? store.createProject(named: "Demo Song") else { return store }
        for (index, name) in ["Guitar", "Vocals", "Shaker"].enumerated() {
            let bins = peaks(bins: 700 + index * 150, seed: 0.05 + Double(index) * 0.04)
            let track = Track(
                name: name,
                fileName: "preview-\(index).caf",
                isMuted: index == 2,
                durationSeconds: Double(bins.count) * PeakStore.binDuration,
                sampleRate: 48_000
            )
            store.addTrack(track, to: project)
            if let fresh = store.project(id: project.id) {
                let data = bins.withUnsafeBufferPointer { Data(buffer: $0) }
                try? data.write(to: store.peaksURL(for: track, in: fresh))
            }
        }
        return store
    }

    /// The seeded "Demo Song" (createProject inserts at index 0).
    @MainActor
    static func demoProject(in store: ProjectStore) -> Project {
        store.projects.first ?? Project(name: "Demo Song")
    }

    /// A meter holding a fixed level, fed via a synthesized buffer.
    static func meter(level: Float = 0.6) -> MeterTap {
        let tap = MeterTap()
        if let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
           let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256) {
            buffer.frameLength = 256
            if let channel = buffer.floatChannelData?[0] {
                for frame in 0..<Int(buffer.frameLength) {
                    channel[frame] = level
                }
            }
            tap.process(buffer)
        }
        return tap
    }
}

/// Presents content the way the app does — as a sheet over a dark backdrop —
/// so FittedSheet's fitted detent sizes realistically in the canvas.
struct SheetPreviewHost<SheetContent: View>: View {
    @ViewBuilder let sheet: SheetContent

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) {
                sheet.fontDesign(.rounded)
            }
    }
}
