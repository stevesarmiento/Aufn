import SwiftUI

/// Shared disclosure motion for controls that open and close in place (the
/// capture wheel in the transport, the mixer sliders on a track card).
/// Anything arriving springs in with a little overshoot so it lands; anything
/// leaving snaps out with almost no bounce so dismissing reads as decisive.
extension Animation {
    static let discloseOpen: Animation = .spring(duration: 0.28, bounce: 0.3)
    static let discloseClose: Animation = .easeOut(duration: 0.16)
}

extension AnyTransition {
    /// Grows out of `anchor` with a blur on the way in and shrinks back into
    /// it on the way out. Pass `edge` to also slide from that side so a
    /// panel appears to unfold rather than just inflate.
    ///
    /// `appearDelay` holds the content invisible while its container is still
    /// making room (the same idea as the swipe-delete button staying hidden
    /// for the first stretch of travel), so it never overlaps neighbours
    /// mid-expand. Leaving is never delayed — dismissal should feel instant.
    static func disclose(anchor: UnitPoint, edge: Edge? = nil, appearDelay: TimeInterval = 0) -> AnyTransition {
        var insertion = AnyTransition.scale(scale: 0.7, anchor: anchor)
            .combined(with: AnyTransition(.blurReplace))
        var removal = AnyTransition.scale(scale: 0.85, anchor: anchor)
            .combined(with: AnyTransition(.blurReplace))
        if let edge {
            insertion = insertion.combined(with: .move(edge: edge))
            removal = removal.combined(with: .move(edge: edge))
        }
        return .asymmetric(
            insertion: insertion.animation(.discloseOpen.delay(appearDelay)),
            removal: removal.animation(.discloseClose)
        )
    }
}
