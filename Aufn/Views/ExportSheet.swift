import SwiftUI
import UIKit

struct ExportSheet: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let project: Project

    @State private var isExporting = false
    @State private var shareItems: ShareItems?
    @State private var exportError: String?
    @State private var bakeTrackVolume = false

    struct ShareItems: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let bake = bakeTrackVolume
                    exportButton("Export Stems (WAV)", systemImage: "square.stack.3d.up") {
                        let folder = try Exporter.exportStems($0, projectName: $1, applyingVolume: bake)
                        return try FileManager.default
                            .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                            .sorted { $0.lastPathComponent < $1.lastPathComponent }
                    }
                    Toggle("Apply track volume", isOn: $bakeTrackVolume)
                } footer: {
                    Text("Each track as its own 24-bit WAV — drop them straight into Logic or Ableton. Stems are raw unless \"Apply track volume\" is on; pan, mute, and solo affect the mixdown only.")
                }

                Section {
                    let bake = bakeTrackVolume
                    exportButton("Share as Zip", systemImage: "doc.zipper") {
                        let folder = try Exporter.exportStems($0, projectName: $1, applyingVolume: bake)
                        return [try Exporter.zip(folder: folder)]
                    }
                    let master = project.masterVolume
                    exportButton("Stereo Mixdown (WAV)", systemImage: "waveform") { stems, name in
                        let rate = stems.map(\.track.sampleRate).max() ?? 48_000
                        return [try Exporter.mixdown(stems, projectName: name, sampleRate: rate, masterVolume: master)]
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isExporting {
                    ProgressView("Exporting…")
                        .padding(24)
                        .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }
            }
            .alert("Export Failed", isPresented: .init(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .sheet(item: $shareItems) { items in
                ActivityView(items: items.urls)
            }
        }
    }

    private func exportButton(
        _ title: String,
        systemImage: String,
        work: @escaping @Sendable ([Exporter.Stem], String) throws -> [URL]
    ) -> some View {
        Button {
            runExport(work)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .disabled(isExporting || project.tracks.isEmpty)
    }

    private func runExport(_ work: @escaping @Sendable ([Exporter.Stem], String) throws -> [URL]) {
        let stems = project.tracks.map { Exporter.Stem(track: $0, audioURL: store.audioURL(for: $0, in: project)) }
        let name = project.name
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let urls = try await Task.detached(priority: .userInitiated) {
                    try work(stems, name)
                }.value
                shareItems = ShareItems(urls: urls)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}

/// Multi-file share sheet (ShareLink can't take a lazily produced [URL]).
struct ActivityView: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview("Export") {
    let store = PreviewData.store()
    SheetPreviewHost {
        ExportSheet(project: PreviewData.demoProject(in: store))
            .environment(store)
    }
    .preferredColorScheme(.dark)
}
