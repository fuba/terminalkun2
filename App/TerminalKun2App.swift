import SwiftUI

@main
struct TerminalKun2App: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            WorkspaceView().environmentObject(store)
                .tint(.primary)
                .onOpenURL { store.open($0) }
                .onChange(of: scenePhase) { _, phase in store.sceneChanged(phase) }
        }
    }
}
