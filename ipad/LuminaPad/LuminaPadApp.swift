import SwiftUI

@main
struct LuminaPadApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()

    var body: some SwiftUI.Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { model.beginForegroundRefresh() }
                .onOpenURL { url in
                    Task { await model.handleDeepLink(url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.beginForegroundRefresh()
            } else {
                model.stopForegroundRefresh()
            }
        }
    }
}
