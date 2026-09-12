import SwiftUI

/// One tile on the projects grid: the project's tint, the name over a
/// tracks/length caption, and along the bottom a play/stop circle beside a
/// dot-matrix thumbnail of the mix. The whole card opens the project; the
/// circle is an overlay so its taps never reach the card. A project with no
/// tracks has nothing to play or draw, so its bottom row is empty.
struct ProjectCard: View {
    let project: Project
    var isPlaying = false
    var showsPlayButton = true
    var onOpen: () -> Void = {}
    var onPlay: () -> Void = {}

    static let cornerRadius: CGFloat = 26
    static let height: CGFloat = 120
    private static let buttonSize: CGFloat = 34

    private var canPlay: Bool { showsPlayButton && !project.tracks.isEmpty }

    var body: some View {
        Button {
            Haptics.tap()
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(project.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(project.caption)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    if canPlay {
                        // Stand-in for the overlaid play button, so the
                        // waveform lays out beside it, not under it.
                        Color.clear
                            .frame(width: Self.buttonSize, height: Self.buttonSize)
                    }
                    if !project.tracks.isEmpty {
                        CardWaveform(project: project)
                            .frame(height: Self.buttonSize)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.height)
            .background(project.tint.color, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(project.name)
        .accessibilityIdentifier("ProjectCard")
        .overlay(alignment: .bottomLeading) {
            if canPlay {
                playButton
                    .padding(16)
                    .transition(.blurReplace)
            }
        }
        .animation(.snappy, value: canPlay)
    }

    private var playButton: some View {
        Button {
            Haptics.tap()
            onPlay()
        } label: {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(.white.opacity(0.25), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Stop \(project.name)" : "Play \(project.name)")
    }
}

/// The card's mix thumbnail: every track's cached peaks combined at effective
/// volume, in the transport tape's dot language. Reads only the small peaks
/// caches — never audio files — and reloads when a take's cache lands.
private struct CardWaveform: View {
    @Environment(ProjectStore.self) private var store
    @Environment(AudioEngineController.self) private var engine

    let project: Project

    @State private var peaks: [Float] = []

    var body: some View {
        // Redraws on a timeline while this card's mix plays so the yellow
        // playhead column tracks the transport; paused (and playhead-less)
        // for every other card.
        TimelineView(.animation(minimumInterval: 0.1, paused: engine.playingProjectID != project.id)) { _ in
            WaveformView(
                peaks: peaks,
                tint: .white.opacity(0.5),
                progress: WaveformView.playbackProgress(
                    elapsed: engine.elapsedSeconds,
                    duration: project.mixLengthSeconds,
                    isActive: engine.playingProjectID == project.id
                )
            )
        }
        .task(id: fingerprint) { await load() }
    }

    /// Reload when the track set, audibility, or a peaks cache changes.
    private var fingerprint: Int {
        var hasher = Hasher()
        for track in project.tracks {
            hasher.combine(track.id)
            hasher.combine(track.volume)
            hasher.combine(track.isMuted)
            hasher.combine(track.isSoloed)
        }
        hasher.combine(project.metronome?.isSoloed ?? false)
        hasher.combine(store.peaksRevision)
        return hasher.finalize()
    }

    private func load() async {
        var trackPeaks: [UUID: [Float]] = [:]
        for track in project.tracks {
            let url = store.peaksURL(for: track, in: project)
            trackPeaks[track.id] = await Task.detached(priority: .utility) {
                PeakStore.loadPeaks(from: url) ?? []
            }.value
        }
        // A superseded load (track set changed mid-flight) must not overwrite
        // the newer result.
        guard !Task.isCancelled else { return }
        peaks = project.combinedMixPeaks(from: trackPeaks)
    }
}

/// Press-scale for the card. A ButtonStyle rather than the kit's
/// `.pressAnimation()` gesture so the context menu's long press still fires.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension Project {
    /// Longest track — the mix length — since tracks play together.
    var mixLengthSeconds: Double {
        tracks.map(\.durationSeconds).max() ?? 0
    }

    /// "3 tracks · 1:24"
    var caption: String {
        "\(tracks.count) track\(tracks.count == 1 ? "" : "s") · \(mixLengthSeconds.timecode)"
    }
}

#Preview("Cards", traits: .sizeThatFitsLayout) {
    let store = PreviewData.store()
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
        ProjectCard(project: PreviewData.demoProject(in: store), isPlaying: true)
        ProjectCard(project: Project(name: "Sketch", tint: .pink))
        ProjectCard(project: Project(name: "Late Night", tint: .indigo))
        ProjectCard(project: Project(name: "Girth", tint: .yellow))
    }
    .padding(20)
    .frame(width: 390)
    .background(Color.black)
    .environment(store)
    .environment(AudioEngineController(store: store))
    .fontDesign(.rounded)
    .preferredColorScheme(.dark)
}
