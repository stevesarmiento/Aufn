import SwiftUI

/// Preferred capture sample rate with the plain-English explainers carried
/// over from the original Aufn. Rates the current input can't grant keep
/// their descriptions and get an "Unavailable" badge (probed live); a project
/// that already has takes shows its locked rate — the selection only shapes
/// future first takes.
struct SampleRatePicker: View {
    @Environment(AudioEngineController.self) private var engine
    @AppStorage("preferredSampleRate") private var preferredSampleRate: Double = 48_000

    /// The open project's locked rate, if it already has takes.
    var lockedRate: Double? = nil

    @State private var supportedRates: Set<Double> = []
    @State private var didProbe = false

    private struct RateOption {
        let rate: Double
        let badge: String
        let icon: String
        let explainer: String
    }

    private let options: [RateOption] = [
        .init(rate: 44_100, badge: "G", icon: "moonphase.waxing.gibbous.inverse",
              explainer: "44.1 kHz: CD quality, smaller file size, suitable for most uses."),
        .init(rate: 48_000, badge: "G+", icon: "moonphase.first.quarter.inverse",
              explainer: "48 kHz: Higher quality, slightly larger file size, common for video."),
        .init(rate: 88_200, badge: "H", icon: "moonphase.waxing.crescent.inverse",
              explainer: "88.2 kHz: Enhanced audio quality, larger file size, for high-fidelity music."),
        .init(rate: 96_000, badge: "H+", icon: "moonphase.new.moon.inverse",
              explainer: "96 kHz: Studio-grade quality, largest file size, suitable for professional audio."),
    ]

    var body: some View {
        SettingsSubPage(title: "Sample Rate") {
            if let lockedRate {
                SettingsFootnote(
                    "This project is locked at \(formatted(lockedRate)) — set by its first take. Your selection here applies to new projects.",
                    systemImageName: "lock"
                )
            }
            ForEach(options, id: \.rate) { option in
                row(for: option)
            }
            if didProbe && supportedRates.count < options.count {
                SettingsFootnote(
                    "Sample rates marked unavailable are not supported by the current microphone. A USB microphone can unlock more sample rates.",
                    systemImageName: "cable.connector"
                )
            }
        }
        .onAppear(perform: probe)
    }

    private func row(for option: RateOption) -> some View {
        let isSupported = !didProbe || supportedRates.contains(option.rate)
        let khz = option.rate / 1000
        let title = "\(option.badge) — \(khz == khz.rounded() ? String(Int(khz)) : String(khz)) kHz"
        return SettingsOptionRow(
            iconName: option.icon,
            title: title,
            caption: option.explainer,
            badge: isSupported ? nil : "Unavailable",
            selected: preferredSampleRate == option.rate,
            enabled: isSupported,
            accessibilityLabelOverride: "Sample rate, \(title)"
        ) {
            preferredSampleRate = option.rate
        }
    }

    /// Probe what the current route grants — only while the transport is idle
    /// (changing the preferred rate mid-take would reconfigure the route).
    private func probe() {
        guard engine.state == .idle else { return }
        supportedRates = AudioSessionController.shared.supportedSampleRates(from: options.map(\.rate))
        didProbe = true
    }

    private func formatted(_ rate: Double) -> String {
        let khz = rate / 1000
        return khz == khz.rounded() ? "\(Int(khz)) kHz" : String(format: "%.1f kHz", khz)
    }
}

#Preview("Unlocked") {
    NavigationStack {
        SampleRatePicker()
            .environment(AudioEngineController(store: ProjectStore()))
    }
    .preferredColorScheme(.dark)
}

#Preview("Locked project") {
    NavigationStack {
        SampleRatePicker(lockedRate: 48_000)
            .environment(AudioEngineController(store: ProjectStore()))
    }
    .preferredColorScheme(.dark)
}
