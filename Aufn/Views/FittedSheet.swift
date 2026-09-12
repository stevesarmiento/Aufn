import SwiftUI

/// Sheet chrome whose minimized detent fits the content's measured height, so
/// nothing gets cut off at the small detent; expandable to .large as a
/// fallback for overflow (content scrolls if it's taller than the screen).
struct FittedSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    @ViewBuilder let content: Content

    @State private var contentHeight: CGFloat = 320

    private var navigationChromeHeight: CGFloat { 64 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .padding(20)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                    contentHeight = height
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(min(contentHeight + navigationChromeHeight, 660)), .large])
        .presentationDragIndicator(.visible)
    }
}

/// Card background matching the app's dark glass row aesthetic, for rows
/// inside FittedSheet content.
extension View {
    func sheetCard() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
    }
}

#Preview("Fitted sheet") {
    SheetPreviewHost {
        FittedSheet(title: "Example") {
            Label("A card row", systemImage: "waveform")
                .font(.headline)
                .sheetCard()
            Text("A footnote explainer, in the style the pickers use for their fine print.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .sheetCard()
        }
    }
    .preferredColorScheme(.dark)
}
