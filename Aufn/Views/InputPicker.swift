import AVFAudio
import SwiftUI

/// Microphone selection, following the SampleRatePicker list pattern.
/// AVAudioSessionPortDescription values stay confined to this @MainActor view.
struct InputPicker: View {
    @Environment(\.dismiss) private var dismiss

    @State private var inputs: [AVAudioSessionPortDescription] = []
    @State private var selectedUID: String?

    private let session = AudioSessionController.shared

    var body: some View {
        NavigationStack {
            List {
                autoRow
                ForEach(inputs, id: \.uid) { input in
                    row(for: input)
                }
            }
            .navigationTitle("Microphone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Your choice is remembered per device — if it disconnects, Aufn falls back to Auto until it returns.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
            .onAppear(perform: refresh)
            .task {
                // Devices can connect while the sheet is open.
                for await _ in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification).map({ _ in () }) {
                    refresh()
                }
            }
        }
    }

    private var autoRow: some View {
        Button {
            session.selectInput(uid: nil, portType: nil)
            selectedUID = nil
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto")
                        .font(.headline)
                    Text("Let iOS pick the best available microphone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedUID == nil {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func row(for input: AVAudioSessionPortDescription) -> some View {
        Button {
            session.selectInput(uid: input.uid, portType: input.portType.rawValue)
            selectedUID = input.uid
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: input.portType))
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(input.portName)
                        .font(.headline)
                    Text(explainer(for: input.portType))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedUID == input.uid {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func refresh() {
        inputs = session.inputsForPicker()
        selectedUID = session.preferredInputUID.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func icon(for portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInMic: "iphone"
        case .bluetoothHFP: "airpods.pro"
        case .usbAudio: "cable.connector"
        case .headsetMic: "headphones"
        default: "mic"
        }
    }

    private func explainer(for portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInMic:
            "The iPhone's studio-tuned mic — best wireless-free quality."
        case .bluetoothHFP:
            "Uses the low-bandwidth headset protocol — noticeably lower quality. Best for scratch takes."
        case .usbAudio:
            "External interface — best quality."
        case .headsetMic:
            "Wired headset mic."
        default:
            "External microphone."
        }
    }
}
