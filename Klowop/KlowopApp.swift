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
            // Keep widgets and reminders in sync whenever the app leaves the foreground.
            if phase == .background || phase == .inactive {
                WidgetCenter.shared.reloadAllTimelines()
                Task { @MainActor in
                    await NotificationService.shared.rescheduleAll(
                        context: container.mainContext)
                    await NotificationService.shared.checkBudgets(
                        context: container.mainContext)
                }
                // NOTE: BGTaskScheduler registration (auto-briefing) is temporarily
                // disabled — its launch-time XPC registration crashes on iOS 27
                // beta 1 when built with the iOS 26.4 SDK. Restore alongside
                // KlowopIntents.swift once building with the Xcode 27 beta.
            }
        }
    }
}
