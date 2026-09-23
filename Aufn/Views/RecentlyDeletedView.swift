import SwiftUI

/// The workspace's trash, laid out like a wallet's activity feed: a header
/// per day, and under it each deleted take as a glyph, its name over a grey
/// caption, and the action on the trailing edge. Restore puts a take back
/// exactly as it was; entries expire after `ProjectStore.trashRetention`.
/// Restoring and purging are idle-only — the engine can't grow the mix while
/// the transport runs.
struct RecentlyDeletedView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(AudioEngineController.self) private var engine

    let projectID: UUID

    @State private var confirmingDeleteAll = false
    @State private var pendingPermanentDelete: DeletedTrack?

    private var entries: [DeletedTrack] {
        (store.project(id: projectID)?.deletedTracks ?? []).sorted { $0.deletedAt > $1.deletedAt }
    }

    private var isIdle: Bool { engine.state == .idle }

    /// Entries grouped by the calendar day they were deleted, newest day first.
    private var days: [(day: Date, entries: [DeletedTrack])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.deletedAt) }
        return grouped.keys.sorted(by: >).map { (day: $0, entries: grouped[$0] ?? []) }
    }

    var body: some View {
        SettingsSubPage(title: "Recently Deleted") {
            if entries.isEmpty {
                emptyState
                    .transition(.blurReplace)
            } else {
                if !isIdle {
                    SettingsFootnote("Restoring is locked while the transport is running.", systemImageName: "lock")
                }
                ForEach(days, id: \.day) { day in
                    SettingsSectionHeader(Self.title(for: day.day))
                    ForEach(day.entries) { entry in
                        DeletedTrackRow(
                            entry: entry,
                            enabled: isIdle,
                            onRestore: { restore(entry) },
                            onDeleteForever: { pendingPermanentDelete = entry }
                        )
                        .transition(.blurReplace)
                    }
                }
                SettingsFootnote("Deleted tracks are kept for 30 days, then removed for good.")
            }
        }
        .animation(.snappy, value: entries)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    confirmingDeleteAll = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                }
                .disabled(entries.isEmpty || !isIdle)
                .accessibilityLabel("Delete All")
            }
        }
        .alert(deleteAllTitle, isPresented: $confirmingDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) { deleteAll() }
        } message: {
            Text("This can't be undone.")
        }
        .alert(
            pendingPermanentDelete.map { "Delete \"\($0.track.name)\" permanently?" } ?? "",
            isPresented: Binding(
                get: { pendingPermanentDelete != nil },
                set: { if !$0 { pendingPermanentDelete = nil } }
            ),
            presenting: pendingPermanentDelete
        ) { entry in
            Button("Cancel", role: .cancel) {}
            Button("Delete Permanently", role: .destructive) { deleteForever(entry) }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private var deleteAllTitle: String {
        let count = entries.count
        return "Delete \(count) track\(count == 1 ? "" : "s") permanently?"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
            Text("Nothing deleted")
                .fontDesign(.rounded)
                .font(.system(size: 16))
                .bold()
                .foregroundStyle(.white.opacity(0.8))
            Text("Tracks you delete stay here for 30 days.")
                .fontDesign(.rounded)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: - Actions

    /// Same orchestration as a row-level mix change: persist, then hand the
    /// engine the fresh project (a no-op while idle, kept for symmetry).
    private func restore(_ entry: DeletedTrack) {
        guard isIdle, let project = store.project(id: projectID) else { return }
        withAnimation(.snappy) {
            store.restoreTrack(id: entry.id, in: project)
        }
        if let fresh = store.project(id: projectID) {
            engine.updateMix(for: fresh)
        }
    }

    private func deleteForever(_ entry: DeletedTrack) {
        guard let project = store.project(id: projectID) else { return }
        Haptics.heavy()
        withAnimation(.snappy) {
            store.permanentlyDeleteTrashedTracks(ids: [entry.id], from: project)
        }
    }

    private func deleteAll() {
        guard let project = store.project(id: projectID) else { return }
        Haptics.heavy()
        withAnimation(.snappy) {
            store.emptyTrash(for: project)
        }
    }
}

/// One trashed take: grade seal or waveform glyph, name over
/// "length · grade", days left, and Restore. Permanent deletion hides in the
/// context menu — restoring is the primary action.
private struct DeletedTrackRow: View {
    let entry: DeletedTrack
    let enabled: Bool
    let onRestore: () -> Void
    let onDeleteForever: () -> Void

    private var track: Track { entry.track }

    private var subtitle: String {
        var parts = [track.durationSeconds.timecode, track.captureMode.label]
        if track.channelCount == 2 { parts.append("ST") }
        return parts.joined(separator: " · ")
    }

    private var daysLeft: Int {
        max(0, Int((entry.expiresAt().timeIntervalSinceNow / 86_400).rounded(.up)))
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.1))
                if let letter = track.captureMode.badgeLetter {
                    Text(letter)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .fontDesign(.rounded)
                    .font(.system(size: 16))
                    .bold()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .fontDesign(.rounded)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("\(daysLeft)d")
                .font(.system(size: 12, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.4))
                .accessibilityLabel("\(daysLeft) days left")

            Button {
                Haptics.tap()
                onRestore()
            } label: {
                Text("Restore")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.15), in: .capsule)
            }
            .buttonStyle(.plain)
            .pressAnimation()
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
            .accessibilityLabel("Restore \(track.name)")
        }
        .settingsCard()
        .contextMenu {
            Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                onDeleteForever()
            }
            .disabled(!enabled)
        }
    }
}

#Preview("Recently deleted") {
    let store = PreviewData.store()
    let project: Project = {
        let project = PreviewData.demoProject(in: store)
        store.deleteTracks(ids: Set(project.tracks.prefix(2).map(\.id)), from: project)
        return project
    }()
    NavigationStack {
        RecentlyDeletedView(projectID: project.id)
    }
    .fontDesign(.rounded)
    .environment(store)
    .environment(AudioEngineController(store: store))
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    let store = PreviewData.store()
    NavigationStack {
        RecentlyDeletedView(projectID: PreviewData.demoProject(in: store).id)
    }
    .fontDesign(.rounded)
    .environment(store)
    .environment(AudioEngineController(store: store))
    .preferredColorScheme(.dark)
}
