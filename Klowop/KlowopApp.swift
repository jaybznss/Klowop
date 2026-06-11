import SwiftUI
import SwiftData
import WidgetKit

@main
struct KlowopApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let container: ModelContainer

    init() {
        do {
            container = try AppGroup.makeModelContainer()
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Keep home-screen widgets in sync whenever the app leaves the foreground.
            if phase == .background || phase == .inactive {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
