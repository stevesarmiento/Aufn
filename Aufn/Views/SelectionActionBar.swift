import SwiftUI

/// Replaces the transport while rows are selected: one glass pill of three
/// labeled segments (Cancel / Delete / Export), the way a wallet's edit mode
/// swaps its tab bar for actions. Shaped glass per segment (plain button +
/// explicit glassEffect — `.buttonStyle(.glass)` blobs non-square labels) so
/// the segments read as one control inside the container.
struct SelectionActionBar: View {
    let canExport: Bool
    let onCancel: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                segment("Cancel", systemImage: "xmark", accessibilityLabel: "Cancel selection") {
                    Haptics.tap()
                    onCancel()
                }
                segment("Delete", systemImage: "trash.fill", tint: .red, accessibilityLabel: "Delete selected") {
                    Haptics.heavy()
                    onDelete()
                }
                segment("Export", systemImage: "square.and.arrow.up", accessibilityLabel: "Export selected") {
                    Haptics.tap()
                    onExport()
                }
                    .disabled(!canExport)
                    .opacity(canExport ? 1 : 0.4)
            }
            .padding(6)
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
        }
        // Same footprint as the transport (96 pt deck + 4 pt), so the scroll
        // inset doesn't jump when the two swap.
        .frame(height: 100)
        .padding(.horizontal, 20)
    }

    private func segment(
        _ title: String,
        systemImage: String,
        tint: Color? = nil,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(tint ?? .primary)
            .frame(width: 96, height: 72)
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .glassEffect(
            tint.map { .regular.tint($0.opacity(0.22)).interactive() } ?? .regular.interactive(),
            in: .rect(cornerRadius: 24)
        )
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("Selection bar") {
    VStack {
        Spacer()
        SelectionActionBar(canExport: true, onCancel: {}, onDelete: {}, onExport: {})
        SelectionActionBar(canExport: false, onCancel: {}, onDelete: {}, onExport: {})
    }
    .fontDesign(.rounded)
    .preferredColorScheme(.dark)
}
