import SwiftUI

@main
struct AufnApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: ProjectStore
    @State private var engine: AudioEngineController

    init() {
        let store = ProjectStore()
        _store = State(initialValue: store)
        _engine = State(initialValue: AudioEngineController(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .fontDesign(.rounded)
                .preferredColorScheme(.dark)
                .environment(store)
                .environment(engine)
        }
        .onChange(of: scenePhase) { _, phase in
            // Background audio keeps a running transport alive; an idle
            // session has no reason to hold the audio route (and other apps'
            // playback) hostage.
            if phase == .background && engine.state == .idle {
                AudioSessionController.shared.deactivate()
            }
        }
    }
}
