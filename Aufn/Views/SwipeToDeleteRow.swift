import SwiftUI

/// Swipe-left-to-reveal delete for rows hosted in a ScrollView/LazyVStack
/// (no List, so no system swipeActions). Styled like a standard list swipe
/// action: full-height red panel with a white trash glyph. A partial swipe
/// snaps open to the button; a full swipe or a tap on the button triggers the
/// delete flow — always through the confirmation dialog.
///
/// Open/closed truth lives in the parent's `openRowID` so exactly one row is
/// open at a time and rebuilt rows render in the correct position.
struct SwipeToDeleteRow<Content: View>: View {
    let id: UUID
    @Binding var openRowID: UUID?
    let deleteTitle: String
    var deleteButtonTitle: String = "Delete Track"
    var deleteMessage: String = "This removes the audio file permanently."
    var deleteAccessibilityLabel: String = "Delete track"
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    // @GestureState (not @State): when the ScrollView steals the touch the
    // drag is CANCELLED — onEnded never runs — and only a gesture state's
    // automatic reset puts the row back. With @State this left rows frozen
    // mid-offset with a stale axis lock, which read as scroll glitches.
    @GestureState(resetTransaction: Transaction(animation: .snappy))
    private var drag = SwipeDrag()
    @State private var confirmingDelete = false
    @State private var rowWidth: CGFloat = 0

    private let revealWidth: CGFloat = 72
    private var isOpen: Bool { openRowID == id }
    private var baseOffset: CGFloat { isOpen ? -revealWidth : 0 }
    // Right-drag past closed rubber-bands; left drag is free so a full swipe
    // can travel the row (standard list behavior).
    private var offset: CGFloat {
        let x = baseOffset + drag.translation
        return x > 0 ? x / 4 : x
    }

    /// Appearance ramp for the delete button: stays invisible for the first
    /// 44 pt of travel so it never peeks out next to the card edge, then
    /// fades/scales in over the rest of the reveal.
    private var revealProgress: CGFloat {
        min(1, max(0, (-offset - 44) / (revealWidth - 44)))
    }
    /// A 48 pt circle while revealing; past the reveal point it stretches
    /// leftward into a pill as the drag continues toward the commit.
    private var buttonWidth: CGFloat {
        min(48 + max(0, -offset - revealWidth), max(48, -offset - 12))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < -0.5 {
                Button {
                    confirmingDelete = true
                } label: {
                    // Native list swipe-action styling: red circle with the
                    // glyph centered (even while stretching into a pill) and
                    // a quiet label underneath.
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(.red)
                            .overlay {
                                Image(systemName: "trash.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: buttonWidth, height: 48)
                        Text("Delete")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .opacity(revealProgress)
                .scaleEffect(0.6 + 0.4 * revealProgress, anchor: .trailing)
                .padding(.trailing, 8)
                .accessibilityLabel(deleteAccessibilityLabel)
            }

            content()
                .offset(x: offset)
                .gesture(dragGesture)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            rowWidth = width
        }
        .sensoryFeedback(trigger: isOpen) { _, isNowOpen in
            isNowOpen ? .impact(weight: .light) : nil
        }
        .confirmationDialog(deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(deleteButtonTitle, role: .destructive) { onDelete() }
        } message: {
            Text(deleteMessage)
        }
        .onChange(of: confirmingDelete) { _, showing in
            // Cancel/dismiss: don't leave the row sitting armed.
            if !showing && isOpen {
                withAnimation(.snappy) { openRowID = nil }
            }
        }
    }

    /// Plain .gesture + explicit axis lock: the row only claims a drag that is
    /// CLEARLY horizontal (1.5× wider than tall); anything ambiguous stays
    /// unlocked so the ScrollView wins ties and scroll starts are never
    /// hijacked by a slightly diagonal flick.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drag) { value, state, _ in
                if state.axis == nil {
                    if Self.isClearlyHorizontal(value.translation) {
                        state.axis = .horizontal
                    } else if abs(value.translation.height) > abs(value.translation.width) {
                        state.axis = .vertical
                    }
                }
                guard state.axis == .horizontal else { return }
                state.translation = value.translation.width
            }
            .onChanged { value in
                if Self.isClearlyHorizontal(value.translation),
                   openRowID != nil, openRowID != id {
                    withAnimation(.snappy) { openRowID = nil }
                }
            }
            .onEnded { value in
                // Judged from the final translation: gesture state may already
                // be reset inside onEnded.
                guard Self.isClearlyHorizontal(value.translation) else { return }
                // Commit needs the finger to actually travel most of the row —
                // a fast flick (large PREDICTED translation) only snaps open.
                let dragged = baseOffset + value.translation.width
                let projected = baseOffset + value.predictedEndTranslation.width
                let commitDistance = max(revealWidth * 2, rowWidth * 0.55)
                withAnimation(.snappy) {
                    if dragged < -commitDistance {
                        // Full swipe: arm the delete flow, settle at the button.
                        openRowID = id
                        confirmingDelete = true
                    } else {
                        openRowID = projected < -revealWidth / 2 ? id : nil
                    }
                }
            }
    }

    private static func isClearlyHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * 1.5
    }
}

/// Transient drag: the row's live offset plus which axis the touch committed
/// to (nil while still ambiguous).
private struct SwipeDrag {
    var translation: CGFloat = 0
    var axis: Axis?
}
