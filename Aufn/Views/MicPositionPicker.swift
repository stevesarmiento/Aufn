import AVFAudio
import SwiftUI

/// The mic-position half of the Microphone settings page: which built-in
/// capsule (and implied pickup pattern) a take uses. Positions the device
/// can't honor get an "Unavailable" badge (probed live). Inert for external
/// inputs.
struct MicPositionSection: View {
    @Environment(AudioEngineController.self) private var engine
    @AppStorage(MicPosition.storageKey) private var micPosition = MicPosition.auto.rawValue

    @State private var availability: [MicPosition: AudioSessionController.MicPositionAvailability] = [:]
    @State private var didProbe = false
    @State private var status: AudioSessionController.MicStatus?

    private let session = AudioSessionController.shared

    var body: some View {
        Group {
            SettingsSectionHeader("Mic Position")
            ForEach(MicPosition.allCases) { position in
                row(for: position)
            }
            if let status, didProbe, !status.isBuiltInMic {
                SettingsFootnote("An external microphone is active — mic position only applies to the iPhone's built-in mic.", systemImageName: "cable.connector")
            }
            SettingsFootnote("Chooses which built-in capsule and pickup pattern iOS uses while recording. Ignored for USB, Bluetooth, and wired mics.")
            if let status, status.isBuiltInMic {
                SettingsFootnote("Now: \(statusLine(status))")
            }
        }
        .onAppear(perform: probe)
        .task {
            // A mic can be plugged in or unplugged while the sheet is open.
            // Only device changes re-probe: the probe itself flips the
            // session mode, and reacting to those category-change
            // notifications would loop.
            let deviceChanges: Set<AVAudioSession.RouteChangeReason> = [.newDeviceAvailable, .oldDeviceUnavailable]
            for await reason in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification).map({ note in
                (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            }) where reason.map(deviceChanges.contains) == true {
                probe()
            }
        }
    }

    private func row(for position: MicPosition) -> some View {
        let availability = didProbe ? (availability[position] ?? .unavailable) : .available
        let isAvailable = availability == .available
        return SettingsOptionRow(
            iconName: position.symbol,
            title: position.name,
            caption: position.caption,
            badge: isAvailable ? nil : "Unavailable",
            selected: micPosition == position.rawValue,
            enabled: isAvailable,
            accessibilityLabelOverride: "Mic position, \(position.name)"
        ) {
            micPosition = position.rawValue
            session.selectMicPosition(position)
            status = session.micStatus
        }
    }

    /// Probe only while idle — it reconfigures the session.
    private func probe() {
        guard engine.state == .idle else { return }
        availability = session.micPositionAvailability()
        status = session.micStatus
        didProbe = true
    }

    private func statusLine(_ status: AudioSessionController.MicStatus) -> String {
        let source = status.dataSourceName ?? "—"
        let pattern = status.polarPattern.map { $0.rawValue.replacingOccurrences(of: "directional", with: "") } ?? "—"
        return "\(source) · \(pattern) · \(status.inputChannels) ch"
    }
}


