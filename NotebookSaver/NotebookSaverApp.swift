import SwiftUI

@main
struct NotebookSaverApp: App {
    @StateObject private var appState = AppStateManager()
    @StateObject private var cameraManager = CameraManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(cameraManager)
                .sheet(isPresented: $appState.showOnboarding) {
                    OnboardingView(isOnboarding: $appState.showOnboarding)
                        .environmentObject(appState)
                }
                .onAppear {
                    if !hasCompletedOnboarding {
                        appState.presentOnboarding()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await DraftsHelper.createPendingDrafts() }
                    }
                }
        }
    }
}


