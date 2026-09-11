import Foundation

/// Confirmation-dialog wording for deleting a selection of rows. The single
/// track and metronome-only cases match the per-row swipe dialogs exactly so
/// the two paths never read differently.
struct SelectionDeleteCopy: Equatable {
    let title: String
    let button: String
    let message: String

    init(trackNames: [String], includesMetronome: Bool) {
        let count = trackNames.count
        switch (count, includesMetronome) {
        case (0, _):
            title = "Remove Metronome?"
            button = "Remove Metronome"
            message = "You can add it back from the menu."
        case (1, false):
            title = "Delete \"\(trackNames[0])\"?"
            button = "Delete Track"
            message = "This removes the audio file permanently."
        case (_, false):
            title = "Delete \(count) tracks?"
            button = "Delete \(count) Tracks"
            message = "This removes their audio files permanently."
        case (1, true):
            title = "Delete \"\(trackNames[0])\" and the metronome?"
            button = "Delete Selected"
            message = "This removes the audio file permanently. You can add the metronome back from the menu."
        default:
            title = "Delete \(count) tracks and the metronome?"
            button = "Delete Selected"
            message = "This removes their audio files permanently. You can add the metronome back from the menu."
        }
    }
}
