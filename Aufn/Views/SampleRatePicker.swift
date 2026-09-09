import SwiftUI

/// Preferred capture sample rate with the plain-English explainers carried
/// over from the original Aufn. The hardware has the final say — this sets
/// the preference requested before the first take of a project.
struct SampleRatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("preferredSampleRate") private var preferredSampleRate: Double = 48_000

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
        NavigationStack {
            List(options, id: \.rate) { option in
                Button {
                    preferredSampleRate = option.rate
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.icon)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(option.badge) — \(option.rate / 1000, format: .number.precision(.fractionLength(0...1))) kHz")
                                .font(.headline)
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
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Sample Rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Applies to new projects. Recording always captures 32-bit float; the hardware may adjust the rate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}
