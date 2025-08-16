import SwiftUI
import UIKit

@main
struct NotebookSaverApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("textExtractorService") private var textExtractorService: String = AppDefaults.textExtractorService
    @StateObject private var appState = AppStateManager()
    
    // Preemptive camera manager for faster startup
    @StateObject private var preemptiveCameraManager = CameraManager(setupOnInit: true)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(preemptiveCameraManager)
                .onAppear {
                    // Configure notifications
                    NotificationManager.shared.configure()
                    
                    if !hasCompletedOnboarding {
                        appState.presentOnboarding()
                    }
                    
                    // Defer Gemini warmup to avoid blocking UI presentation
                    if hasCompletedOnboarding && textExtractorService == TextExtractorType.gemini.rawValue {
                        Task.detached(priority: .background) {
                            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                            await GeminiService.warmUpConnection()
                        }
                    }
                    
                    // Initialize models on first launch
                    initializeModelsIfNeeded()
                }
                .sheet(isPresented: $appState.showOnboarding) {
                    OnboardingView(isOnboarding: $appState.showOnboarding)
                        .environmentObject(appState)
                        .interactiveDismissDisabled()
                }
        }
    }
    
    // Initialize models on first launch only
    private func initializeModelsIfNeeded() {
        let modelService = GeminiModelService.shared
        
        // Only fetch on first launch and if we have an API key
        if modelService.shouldFetchModels, let _ = KeychainService.loadAPIKey() {
            Task.detached(priority: .background) {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                do {
                    let _ = try await modelService.fetchAvailableModels()
                    print("Models fetched successfully on first launch")
                } catch {
                    print("Failed to fetch models on first launch: \(error)")
                    // This is non-critical, the app will use default models
                }
            }
        }
    }
}
