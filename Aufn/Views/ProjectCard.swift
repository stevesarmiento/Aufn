import SwiftUI

/// One tile on the projects grid: the project's tint, name and a
/// tracks/length caption, plus a play/stop circle that drives the transport
/// without opening the workspace. The whole card opens the project; the
/// circle is an overlay so its taps never reach the card. A project with no
/// tracks has nothing to play, so it shows no circle at all.
struct ProjectCard: View {
    let project: Project
    var isPlaying = false
    var showsPlayButton = true
    var onOpen: () -> Void = {}
    var onPlay: () -> Void = {}

    static let cornerRadius: CGFloat = 26
    static let height: CGFloat = 120

    private var canPlay: Bool { showsPlayButton && !project.tracks.isEmpty }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                Text(project.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(project.caption)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.height)
            .background(project.tint.color, in: .rect(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
        .accessibilityLabel(project.name)
        .accessibilityIdentifier("ProjectCard")
        .overlay(alignment: .topTrailing) {
            if canPlay {
                playButton
                    .padding(12)
                    .transition(.blurReplace)
            }
        }
        .animation(.snappy, value: canPlay)
    }

    private var playButton: some View {
        Button {
            Haptics.soft()
            onPlay()
        } label: {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.25), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Stop \(project.name)" : "Play \(project.name)")
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
    .fontDesign(.rounded)
    .preferredColorScheme(.dark)
}
