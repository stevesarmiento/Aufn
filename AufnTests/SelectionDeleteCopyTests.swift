import Testing
@testable import Aufn

struct SelectionDeleteCopyTests {
    @Test func singleTrackMatchesTheRowDialog() {
        let copy = SelectionDeleteCopy(trackNames: ["Track 2"], includesMetronome: false)
        #expect(copy.title == "Delete \"Track 2\"?")
        #expect(copy.button == "Delete Track")
        #expect(copy.message == "You can restore it from Recently Deleted for 30 days.")
    }

    @Test func metronomeOnlyMatchesTheRowDialog() {
        let copy = SelectionDeleteCopy(trackNames: [], includesMetronome: true)
        #expect(copy.title == "Remove Metronome?")
        #expect(copy.button == "Remove Metronome")
        #expect(copy.message == "You can add it back from the menu.")
    }

    @Test func severalTracksCountThem() {
        let copy = SelectionDeleteCopy(trackNames: ["A", "B", "C"], includesMetronome: false)
        #expect(copy.title == "Delete 3 tracks?")
        #expect(copy.button == "Delete 3 Tracks")
        #expect(copy.message == "You can restore them from Recently Deleted for 30 days.")
    }

    @Test func oneTrackPlusMetronome() {
        let copy = SelectionDeleteCopy(trackNames: ["Vox"], includesMetronome: true)
        #expect(copy.title == "Delete \"Vox\" and the metronome?")
        #expect(copy.button == "Delete Selected")
        #expect(copy.message.contains("restore it from Recently Deleted"))
        #expect(copy.message.contains("metronome back"))
    }

    @Test func severalTracksPlusMetronome() {
        let copy = SelectionDeleteCopy(trackNames: ["A", "B"], includesMetronome: true)
        #expect(copy.title == "Delete 2 tracks and the metronome?")
        #expect(copy.button == "Delete Selected")
        #expect(copy.message.contains("restore them from Recently Deleted"))
    }
}
