import AVFAudio
import SwiftUI

/// Which built-in capsule (and implied pickup pattern) a take uses. Matches
/// the Microphone sheet's card rows; positions the device can't honor get an
/// "Unavailable" badge (probed live). Inert for external inputs.
struct MicPositionPicker: View {
    @Environment(AudioEngineController.self) private var engine
    @AppStorage(MicPosition.storageKey) private var micPosition = MicPosition.auto.rawValue

    @State private var availability: [MicPosition: AudioSessionController.MicPositionAvailability] = [:]
    @State private var didProbe = false
    @State private var status: AudioSessionController.MicStatus?

    private let session = AudioSessionController.shared

    var body: some View {
        FittedSheet(title: "Mic Position") {
            ForEach(MicPosition.allCases) { position in
                row(for: position)
            }
            if let status, didProbe, !status.isBuiltInMic {
                Label("An external microphone is active — mic position only applies to the iPhone's built-in mic.", systemImage: "cable.connector")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .sheetCard()
            }
            Text("Chooses which built-in capsule and pickup pattern iOS uses while recording. Ignored for USB, Bluetooth, and wired mics. Stereo records a two-channel take and needs the TAPE capture mode — RAW skips the processing that builds it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .sheetCard()
            if let status, status.isBuiltInMic {
                Text("Now: \(statusLine(status))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
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
        return Button {
            micPosition = position.rawValue
            session.selectMicPosition(position)
            status = session.micStatus
        } label: {
            HStack(spacing: 12) {
                Image(systemName: position.symbol)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(position.name)
                            .font(.headline)
                        if !isAvailable {
                            Text(availability == .requiresTape ? "TAPE only" : "Unavailable")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: .capsule)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(position.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if micPosition == position.rawValue {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .sheetCard()
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.55)
        .accessibilityLabel("Mic position, \(position.name)")
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

#Preview("Mic Position") {
    SheetPreviewHost {
        MicPositionPicker()
    }
    .preferredColorScheme(.dark)
}
