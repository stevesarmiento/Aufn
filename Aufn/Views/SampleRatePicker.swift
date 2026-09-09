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
        FittedSheet(title: "Sample Rate") {
            if let lockedRate {
                Label(
                    "This project is locked at \(formatted(lockedRate)) — set by its first take. Your selection here applies to new projects.",
                    systemImage: "lock"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .sheetCard()
            }
            ForEach(options, id: \.rate) { option in
                row(for: option)
            }
            if didProbe && supportedRates.count < options.count {
                Label(
                    "Sample rates marked unavailable are not supported by the current microphone. A USB microphone can unlock more sample rates.",
                    systemImage: "cable.connector"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .sheetCard()
            }
        }
        .onAppear(perform: probe)
    }

    private func row(for option: RateOption) -> some View {
        let isSupported = !didProbe || supportedRates.contains(option.rate)
        return Button {
            preferredSampleRate = option.rate
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.icon)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(option.badge) — \(option.rate / 1000, format: .number.precision(.fractionLength(0...1))) kHz")
                            .font(.headline)
                        if !isSupported {
                            Text("Unavailable")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: .capsule)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(option.explainer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if preferredSampleRate == option.rate {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .sheetCard()
        }
        .buttonStyle(.plain)
        .disabled(!isSupported)
        .opacity(isSupported ? 1 : 0.55)
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
