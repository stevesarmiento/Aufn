import SwiftUI
import UIKit

/// The export drawer, raised from the settings toolbar's share button. A
/// short sheet of kit-styled action rows; each runs its export off the main
/// actor and hands the results to the system share sheet.
struct ExportDrawer: View {
    @Environment(ProjectStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let project: Project
    /// Scope the drawer to a selection; `nil` exports the whole project.
    var trackIDs: Set<UUID>? = nil

    @State private var isExporting = false
    @State private var shareItems: ShareItems?
    @State private var exportError: String?
    @State private var bakeTrackVolume = false

    struct ShareItems: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    /// The tracks this drawer exports, in project order.
    private var exportTracks: [Track] { project.tracks(limitedTo: trackIDs) }
    private var isScoped: Bool { trackIDs != nil && exportTracks.count != project.tracks.count }

    var body: some View {
        NavigationStack {
            SettingsSubPage(title: "Export", paintsBackdrop: false) {
                content
            }
            .containerBackground(.clear, for: .navigation)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        // Sized to its rows so it reads as a drawer over the settings sheet,
        // draggable to full height if the fine print needs the room.
        .presentationDetents([.height(520), .large])
        .presentationDragIndicator(.visible)
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

    @ViewBuilder
    private var content: some View {
            if isScoped {
                SettingsFootnote("Exporting \(exportTracks.count) of \(project.tracks.count) tracks.")
            }
            SettingsSectionHeader("Stems")
            exportRow("Export Stems (WAV)", iconName: "square.stack.3d.up", capturing: bakeTrackVolume) { bake in
                { stems, name in
                    let folder = try Exporter.exportStems(stems, projectName: name, applyingVolume: bake)
                    return try FileManager.default
                        .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                        .sorted { $0.lastPathComponent < $1.lastPathComponent }
                }
            }
            SettingsToggle(title: "Apply track volume", systemImageName: "slider.horizontal.3", isOn: $bakeTrackVolume)
            SettingsFootnote("Each track as its own 24-bit WAV — drop them straight into Logic or Ableton. Stems are raw unless \"Apply track volume\" is on; pan, mute, and solo affect the mixdown only.")

            SettingsSectionHeader("Mix")
            exportRow("Share as Zip", iconName: "doc.zipper", capturing: bakeTrackVolume) { bake in
                { stems, name in
                    let folder = try Exporter.exportStems(stems, projectName: name, applyingVolume: bake)
                    return [try Exporter.zip(folder: folder)]
                }
            }
            exportRow("Stereo Mixdown (WAV)", iconName: "waveform", capturing: project.masterVolume) { master in
                { stems, name in
                    let rate = stems.map(\.track.sampleRate).max() ?? 48_000
                    return [try Exporter.mixdown(stems, projectName: name, sampleRate: rate, masterVolume: master)]
                }
            }
    }

    /// `capturing` snapshots the one mutable value each export needs on the
    /// main actor, so the detached work closure stays Sendable.
    private func exportRow<Captured>(
        _ title: String,
        iconName: String,
        capturing value: Captured,
        work: (Captured) -> @Sendable ([Exporter.Stem], String) throws -> [URL]
    ) -> some View {
        let job = work(value)
        return SettingsLinkRow(iconName: iconName, title: title, chevronIconName: "square.and.arrow.up") {
            runExport(job)
        }
        .disabled(isExporting || exportTracks.isEmpty)
        .opacity(isExporting || exportTracks.isEmpty ? 0.5 : 1)
    }

    private func runExport(_ work: @escaping @Sendable ([Exporter.Stem], String) throws -> [URL]) {
        let stems = exportTracks.map { Exporter.Stem(track: $0, audioURL: store.audioURL(for: $0, in: project)) }
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
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ExportDrawer(project: PreviewData.demoProject(in: store))
                .environment(store)
        }
        .preferredColorScheme(.dark)
}
