import SwiftUI
import UIKit

/// A UIPickerView wrapper for the capture-mode wheel. Wrapping UIKit directly
/// lets us strip the default gray selection bubble so the selected row reads
/// over our own black scrim (matching the timer), and style rows in the accent
/// with the rounded font. Native momentum, snap, and haptics are preserved.
struct CaptureWheel: UIViewRepresentable {
    let modes: [CaptureMode]
    @Binding var selection: String
    /// Called whenever a different row passes under the selection indicator
    /// while the wheel is scrolling — the mode being considered, before it
    /// is committed. UIPickerView has no scroll delegate, so the coordinator
    /// polls `selectedRow` on a display link while the wheel is on screen.
    var onHighlight: (CaptureMode) -> Void = { _ in }
    /// Called when the wheel settles on a row after the user lets go — commit
    /// and dismiss in one motion.
    var onCommit: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.backgroundColor = .clear
        context.coordinator.startTrackingHighlight(of: picker)
        return picker
    }

    static func dismantleUIView(_ picker: UIPickerView, coordinator: Coordinator) {
        coordinator.stopTrackingHighlight()
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        if let index = modes.firstIndex(where: { $0.rawValue == selection }),
           picker.selectedRow(inComponent: 0) != index {
            picker.selectRow(index, inComponent: 0, animated: false)
        }
        // Clear the gray rounded selection background so the selected row sits
        // on our own black scrim. Clear-only (never hide) so we can't
        // accidentally hide row content during a layout pass.
        DispatchQueue.main.async {
            for subview in picker.subviews {
                subview.backgroundColor = .clear
            }
        }
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: CaptureWheel
        private let feedback = UISelectionFeedbackGenerator()
        private weak var picker: UIPickerView?
        private var displayLink: CADisplayLink?
        private var highlightedRow: Int?

        init(_ parent: CaptureWheel) { self.parent = parent }

        /// The display link retains its target; `stopTrackingHighlight` (from
        /// dismantle) breaks the cycle when the wheel leaves the screen.
        func startTrackingHighlight(of picker: UIPickerView) {
            self.picker = picker
            let link = CADisplayLink(target: self, selector: #selector(pollHighlight))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stopTrackingHighlight() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func pollHighlight() {
            guard let picker else { return }
            let row = picker.selectedRow(inComponent: 0)
            guard row != highlightedRow, parent.modes.indices.contains(row) else { return }
            highlightedRow = row
            parent.onHighlight(parent.modes[row])
        }

        func numberOfComponents(in _: UIPickerView) -> Int { 1 }

        func pickerView(_: UIPickerView, numberOfRowsInComponent _: Int) -> Int {
            parent.modes.count
        }

        func pickerView(_: UIPickerView, rowHeightForComponent _: Int) -> CGFloat { 30 }

        func pickerView(_: UIPickerView, viewForRow row: Int, forComponent _: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.text = parent.modes[row].label
            label.textAlignment = .center
            label.textColor = UIColor(Color.accentColor)
            let base = UIFont.systemFont(ofSize: 14, weight: .heavy)
            label.font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 14) } ?? base
            return label
        }

        func pickerView(_: UIPickerView, didSelectRow row: Int, inComponent _: Int) {
            feedback.selectionChanged()
            parent.selection = parent.modes[row].rawValue
            parent.onCommit()
        }
    }
}
