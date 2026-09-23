import Foundation

/// A take in the workspace's trash: the full `Track` snapshot, so a restore
/// brings back name, levels, mute/solo and printed grade exactly, plus when
/// it was deleted so the entry can expire. Its audio and peaks wait in the
/// project's `trash/` directory, keyed by the track id.
struct DeletedTrack: Identifiable, Codable, Equatable, Hashable {
    var track: Track
    var deletedAt: Date

    var id: UUID { track.id }

    /// When the launch-time sweep removes this entry for good.
    func expiresAt(retention: TimeInterval = ProjectStore.trashRetention) -> Date {
        deletedAt.addingTimeInterval(retention)
    }
}
