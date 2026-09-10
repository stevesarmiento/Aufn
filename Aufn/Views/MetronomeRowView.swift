import SwiftUI

/// The metronome's row in the track list: header styled like a track (M/S +
/// settings disclosure, no waveform) with an inline panel for tempo, volume,
/// meter, click sound, and count-in.
struct MetronomeRowView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(AudioEngineController.self) private var engine

    let settings: MetronomeSettings
    let project: Project

    @State private var isExpanded = false
    @State private var bpm: Double = 120
    @State private var volume: Float = 0.8

    var body: some View {
        TrackCard {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    // Passing nil while silenced parks the grid as a dim
                    // static glyph, so it both stills and quiets with the click.
                    MetronomeBeatGridView(
                        settings: settings,
                        clickStartDate: project.isMetronomeAudible ? engine.clickStartDate : nil
                    )
                    Text("Metronome")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .opacity(project.isMetronomeAudible ? 1 : 0.4)
                        .layoutPriority(-1)
                    Spacer(minLength: 8)
                    Text("\(settings.bpm) BPM · \(settings.beatsPerBar)/4")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                    RoundToggle(letter: "M", isOn: settings.isMuted, tint: .orange, label: "Mute metronome") {
                        var updated = settings
                        updated.isMuted.toggle()
                        persist(updated)
                    }
                    RoundToggle(letter: "S", isOn: settings.isSoloed, tint: .yellow, label: "Solo metronome") {
                        var updated = settings
                        updated.isSoloed.toggle()
                        persist(updated)
                    }
                    RoundToggle(systemImage: "slider.horizontal.3", isOn: isExpanded, tint: .accentColor, label: "Metronome settings") {
                        withAnimation(isExpanded ? .discloseClose : .discloseOpen) {
                            isExpanded.toggle()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, isExpanded ? 0 : 12)

                if isExpanded {
                    settingsControls
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        // Same bouncy-in / instant-out unfold as the track
                        // mixer; the controls wait a beat while the card grows.
                        .transition(.disclose(anchor: .top, edge: .top, appearDelay: 0.06))
                        // Below the header so the expand reveals from
                        // underneath instead of sliding over it.
                        .zIndex(-1)
                }
            }
            // Never shorter than SwipeToDeleteRow's delete underlay (~74 pt),
            // so the row's height can't jump while swiping.
            .frame(minHeight: 80)
        }
        .task(id: settings) {
            bpm = Double(settings.bpm)
            volume = settings.volume
        }
    }

    /// Slider ticks drive the live engine/readout only; disk writes happen
    /// once per gesture, on release. Pickers persist immediately.
    private var settingsControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "metronome")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                Slider(value: $bpm, in: 40...240, step: 1) { editing in
                    if !editing {
                        var updated = settings
                        updated.bpm = Int(bpm)
                        persist(updated)
                        engine.updateMetronome(updated)
                    }
                }
                .tint(.white.opacity(0.6))
                .accessibilityLabel("Metronome tempo")
                Text("\(Int(bpm))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 16)
                Slider(
                    value: Binding(
                        get: { volume },
                        // Push EFFECTIVE volume so dragging a muted/solo-silenced
                        // click doesn't audibly unmute it; raw volume persists.
                        set: { volume = $0; engine.setMetronomeVolume(project.isMetronomeAudible ? $0 : 0) }
                    ),
                    in: 0...1
                ) { editing in
                    if !editing {
                        var updated = settings
                        updated.volume = volume
                        persist(updated)
                    }
                }
                .tint(.white.opacity(0.6))
                .accessibilityLabel("Metronome volume")
            }
            pickerRow(systemImage: "music.note.list", label: "Beats per bar") {
                Picker("Beats per bar", selection: beatsPerBarBinding) {
                    ForEach(2...7, id: \.self) { beats in
                        Text("\(beats)").tag(beats)
                    }
                }
            }
            pickerRow(systemImage: "waveform", label: "Click sound") {
                Picker("Click sound", selection: soundBinding) {
                    ForEach(ClickSound.allCases, id: \.self) { sound in
                        Text(sound.label).tag(sound)
                    }
                }
            }
            pickerRow(systemImage: "timer", label: "Count-in") {
                Picker("Count-in", selection: countInBinding) {
                    Text("Off").tag(0)
                    Text("1 bar").tag(1)
                    Text("2 bars").tag(2)
                }
            }
            Text("Count-in plays before recording starts.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pickerRow(systemImage: String, label: String, @ViewBuilder picker: () -> some View) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            picker()
                .pickerStyle(.segmented)
                .accessibilityLabel(label)
        }
    }

    private var beatsPerBarBinding: Binding<Int> {
        Binding(
            get: { settings.beatsPerBar },
            set: { beats in
                var updated = settings
                updated.beatsPerBar = beats
                persist(updated)
                engine.updateMetronome(updated)
            }
        )
    }

    private var soundBinding: Binding<ClickSound> {
        Binding(
            get: { settings.sound },
            set: { sound in
                var updated = settings
                updated.sound = sound
                persist(updated)
                engine.updateMetronome(updated)
            }
        )
    }

    // Count-in is read at the next record start; no live engine call needed.
    private var countInBinding: Binding<Int> {
        Binding(
            get: { settings.countInBars },
            set: { bars in
                var updated = settings
                updated.countInBars = bars
                persist(updated)
            }
        )
    }

    /// Persist, then live-update the engine mix from the FRESH project — solo
    /// audibility derives from the whole track list plus the metronome, and
    /// the row's `project` is a pre-toggle snapshot.
    private func persist(_ updated: MetronomeSettings) {
        guard var fresh = store.project(id: project.id) else { return }
        fresh.metronome = updated
        store.update(fresh)
        engine.updateMix(for: fresh)
    }
}

#Preview("Metronome row") {
    @Previewable @State var openID: UUID?
    let store = PreviewData.store()
    let project: Project = {
        var project = PreviewData.demoProject(in: store)
        project.metronome = MetronomeSettings(bpm: 96, countInBars: 1)
        store.update(project)
        return project
    }()
    ScrollView {
        LazyVStack(spacing: 12) {
            if let settings = project.metronome {
                SwipeToDeleteRow(
                    id: MetronomeSettings.rowID,
                    openRowID: $openID,
                    deleteTitle: "Remove Metronome?",
                    onDelete: {}
                ) {
                    MetronomeRowView(settings: settings, project: project)
                }
            }
        }
        .padding()
    }
    .fontDesign(.rounded)
    .environment(store)
    .environment(AudioEngineController(store: store))
    .preferredColorScheme(.dark)
}
