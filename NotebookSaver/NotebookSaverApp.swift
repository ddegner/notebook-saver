import SwiftUI

@main
struct NotebookSaverApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("textExtractorService") private var textExtractorService: String = AppDefaults.textExtractorService
    @StateObject private var appState = AppStateManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    if !hasCompletedOnboarding {
                        appState.presentOnboarding()
                    }
                    
                    // Defer Gemini warmup to avoid blocking UI presentation
                    if hasCompletedOnboarding && textExtractorService == TextExtractorType.gemini.rawValue {
                        // Delay by 1 second to prioritize UI rendering
                        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                            Task.detached(priority: .background) {
                                await GeminiService.warmUpConnection()
                            }
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
            // Delay model fetching to not block UI
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                Task.detached(priority: .background) {
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
}
