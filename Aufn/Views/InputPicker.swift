import AVFAudio
import SwiftUI

/// The input-device half of the Microphone settings page.
/// AVAudioSessionPortDescription values stay confined to this @MainActor view.
struct InputDeviceSection: View {
    @Environment(AudioEngineController.self) private var engine
    @State private var inputs: [AVAudioSessionPortDescription] = []
    @State private var selectedUID: String?

    private let session = AudioSessionController.shared

    var body: some View {
        Group {
            SettingsSectionHeader("Input Device")
            autoRow
            ForEach(inputs, id: \.uid) { input in
                row(for: input)
            }
            SettingsFootnote("Your choice is remembered per device — if it disconnects, Aufn falls back to Auto until it returns.")
        }
        .onAppear(perform: refresh)
        .onDisappear {
            // The picker widened the category to HFP so Bluetooth mics would
            // enumerate; put the route back to the persisted choice now
            // rather than leaving AirPods in headset quality until the next
            // transport start.
            if engine.state == .idle {
                try? session.configure()
            }
        }
        .task {
            // Devices can connect while the sheet is open.
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification).map({ _ in () }) {
                refresh()
            }
        }
    }

    private var autoRow: some View {
        SettingsOptionRow(
            iconName: "wand.and.stars",
            title: "Auto",
            caption: "Let iOS pick the best available microphone.",
            selected: selectedUID == nil,
            accessibilityLabelOverride: "Input device, Auto"
        ) {
            session.selectInput(uid: nil, portType: nil)
            selectedUID = nil
        }
    }

    private func row(for input: AVAudioSessionPortDescription) -> some View {
        SettingsOptionRow(
            iconName: icon(for: input.portType),
            title: input.portName,
            caption: explainer(for: input.portType),
            selected: selectedUID == input.uid,
            accessibilityLabelOverride: "Input device, \(input.portName)"
        ) {
            session.selectInput(uid: input.uid, portType: input.portType.rawValue)
            selectedUID = input.uid
        }
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

#Preview("Microphone") {
    NavigationStack {
        MicrophoneSettingsView()
            .environment(AudioEngineController(store: ProjectStore()))
    }
    .preferredColorScheme(.dark)
}
