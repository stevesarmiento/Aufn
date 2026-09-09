import SwiftUI
import UIKit

/// A UIPickerView wrapper for the capture-mode wheel. Wrapping UIKit directly
/// lets us strip the default gray selection bubble so the selected row reads
/// over our own black scrim (matching the timer), and style rows in the accent
/// with the rounded font. Native momentum, snap, and haptics are preserved.
struct CaptureWheel: UIViewRepresentable {
    let modes: [CaptureMode]
    @Binding var selection: String
    /// Called when the wheel settles on a row after the user lets go — commit
    /// and dismiss in one motion.
    var onCommit: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        if let index = modes.firstIndex(where: { $0.rawValue == selection }),
           picker.selectedRow(inComponent: 0) != index {
            picker.selectRow(index, inComponent: 0, animated: false)
        }
        // Strip the system selection indicator after layout: the thin divider
        // lines are hidden and the gray rounded selection background is cleared.
        // Deferred so subview sizes are real — doing it pre-layout (everything
        // zero-height) would hide the whole wheel.
        DispatchQueue.main.async {
            for subview in picker.subviews {
                let height = subview.bounds.height
                if height > 0.1 && height < 1.5 {
                    subview.isHidden = true
                } else {
                    subview.backgroundColor = .clear
                }
            }
        }
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: CaptureWheel
        private let feedback = UISelectionFeedbackGenerator()

        init(_ parent: CaptureWheel) { self.parent = parent }

        func numberOfComponents(in _: UIPickerView) -> Int { 1 }

        func pickerView(_: UIPickerView, numberOfRowsInComponent _: Int) -> Int {
            parent.modes.count
        }

        func pickerView(_: UIPickerView, rowHeightForComponent _: Int) -> CGFloat { 34 }

        func pickerView(_: UIPickerView, viewForRow row: Int, forComponent _: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.text = parent.modes[row].label
            label.textAlignment = .center
            label.textColor = UIColor(Color.accentColor)
            let base = UIFont.systemFont(ofSize: 17, weight: .heavy)
            label.font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 17) } ?? base
            return label
        }

        func pickerView(_: UIPickerView, didSelectRow row: Int, inComponent _: Int) {
            feedback.selectionChanged()
            parent.selection = parent.modes[row].rawValue
            parent.onCommit()
        }
    }
}
