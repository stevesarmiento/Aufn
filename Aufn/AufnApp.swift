import SwiftUI

@main
struct AufnApp: App {
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
                .environment(store)
                .environment(engine)
        }
    }
}
