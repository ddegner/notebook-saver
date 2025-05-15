import SwiftUI

@main
struct NotebookSaverApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("textExtractorService") private var textExtractorService: String = TextExtractorType.gemini.rawValue // Default to Gemini
    @State private var showOnboardingSheet = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    if !hasCompletedOnboarding {
                        showOnboardingSheet = true
                    }
                    
                    // Register for onboarding notification immediately - this is UI critical
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("ShowOnboarding"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        showOnboardingSheet = true
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
                }
                .sheet(isPresented: $showOnboardingSheet) {
                    OnboardingView(isOnboarding: $showOnboardingSheet)
                        .interactiveDismissDisabled()
                }
        }
    }
}
