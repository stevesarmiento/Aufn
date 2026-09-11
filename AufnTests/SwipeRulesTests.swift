import CoreGraphics
import Testing
@testable import Aufn

struct SwipeRulesTests {
    private let reveal = SwipeRules.revealWidth   // 56

    @Test func offsetRubberBandsOnlyTheDisabledDirection() {
        #expect(SwipeRules.offset(base: 0, translation: 40, canDelete: true, canSelect: false) == 10)
        #expect(SwipeRules.offset(base: 0, translation: 40, canDelete: true, canSelect: true) == 40)
        #expect(SwipeRules.offset(base: 0, translation: -40, canDelete: false, canSelect: true) == -10)
        #expect(SwipeRules.offset(base: 0, translation: -40, canDelete: true, canSelect: true) == -40)
    }

    @Test func cardOnlyCreepsPastTheReveal() {
        // 40 pt of excess becomes 10: the card never slides across the row.
        #expect(SwipeRules.offset(base: 0, translation: reveal + 40, canDelete: true, canSelect: true) == reveal + 10)
        #expect(SwipeRules.offset(base: 0, translation: -(reveal + 40), canDelete: true, canSelect: true) == -(reveal + 10))
        // Open row dragged further left creeps too.
        #expect(SwipeRules.offset(base: -reveal, translation: -20, canDelete: true, canSelect: true) == -(reveal + 5))
    }

    @Test func closingAnOpenDeleteRowRubberBandsPastZero() {
        // 24 pt past closed, damped to 6: select is never reachable from an armed delete.
        #expect(SwipeRules.offset(base: -reveal, translation: reveal + 24, canDelete: true, canSelect: true) == 6)
    }

    @Test func panelWidthTucksUnderTheCard() {
        #expect(SwipeRules.panelWidth(travel: 0) == 16)
        #expect(SwipeRules.panelWidth(travel: reveal) == reveal + 16)
        #expect(SwipeRules.panelWidth(travel: -5) == 16)
    }

    @Test func iconRampsInOver12To40Points() {
        #expect(SwipeRules.iconProgress(travel: 0) == 0)
        #expect(SwipeRules.iconProgress(travel: 12) == 0)
        #expect(SwipeRules.iconProgress(travel: 26) == 0.5)
        #expect(SwipeRules.iconProgress(travel: 40) == 1)
        #expect(SwipeRules.iconProgress(travel: 200) == 1)
    }

    @Test func fillReachesTheActionColourAtTheReveal() {
        #expect(SwipeRules.fillProgress(travel: 0) == 0)
        #expect(SwipeRules.fillProgress(travel: reveal / 2) == 0.5)
        #expect(SwipeRules.fillProgress(travel: reveal) == 1)
        #expect(SwipeRules.fillProgress(travel: reveal * 3) == 1)
    }

    @Test func deleteArmsAtTheRevealWithNoRestingState() {
        #expect(SwipeRules.outcome(base: 0, translation: -reveal, canDelete: true, canSelect: true) == .commitDelete)
        #expect(SwipeRules.outcome(base: 0, translation: -300, canDelete: true, canSelect: true) == .commitDelete)
        #expect(SwipeRules.outcome(base: 0, translation: -(reveal - 1), canDelete: true, canSelect: true) == .close)
        #expect(SwipeRules.outcome(base: 0, translation: -10, canDelete: true, canSelect: true) == .close)
        // Dragging the armed (alert-showing) row back toward closed closes it.
        #expect(SwipeRules.outcome(base: -reveal, translation: 40, canDelete: true, canSelect: true) == .close)
    }

    @Test func selectTogglesOnlyPastTheFullReveal() {
        #expect(SwipeRules.outcome(base: 0, translation: reveal - 1, canDelete: true, canSelect: true) == .close)
        #expect(SwipeRules.outcome(base: 0, translation: reveal, canDelete: true, canSelect: true) == .toggleSelect)
        #expect(SwipeRules.outcome(base: 0, translation: 300, canDelete: true, canSelect: true) == .toggleSelect)
        // From an armed delete row a long right drag only closes.
        #expect(SwipeRules.outcome(base: -reveal, translation: 200, canDelete: true, canSelect: true) == .close)
        #expect(SwipeRules.outcome(base: 0, translation: 200, canDelete: true, canSelect: false) == .close)
    }

    @Test func selectionModeDisablesDelete() {
        #expect(SwipeRules.outcome(base: 0, translation: -300, canDelete: false, canSelect: true) == .close)
    }
}
