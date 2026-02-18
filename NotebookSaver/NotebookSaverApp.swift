import SwiftUI

@main
struct NotebookSaverApp: App {
    @StateObject private var appState = AppStateManager()
    @StateObject private var cameraManager = CameraManager()
    @AppStorage(SettingsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register default values for all settings
        let defaults: [String: Any] = [
            SettingsKey.selectedModelId: "gemini-2.5-flash-lite",
            SettingsKey.textExtractorService: "vision",
            SettingsKey.savePhotosEnabled: true,
            SettingsKey.addDraftTagEnabled: true,
            SettingsKey.draftsTag: "notebook",
            SettingsKey.photoFolderName: "notebook",
            SettingsKey.visionRecognitionLevel: "accurate",
            SettingsKey.visionUsesLanguageCorrection: true,
            SettingsKey.thinkingEnabled: false,
            SettingsKey.geminiPhotoTokenBudget: GeminiPhotoTokenBudget.high.rawValue
        ]
        UserDefaults.standard.register(defaults: defaults)
        
        // Migrate old TextExtractorType values (UI strings -> stable identifiers)
        if let oldValue = UserDefaults.standard.string(forKey: SettingsKey.textExtractorService) {
            switch oldValue {
            case "Cloud":
                UserDefaults.standard.set("gemini", forKey: SettingsKey.textExtractorService)
            case "Local":
                UserDefaults.standard.set("vision", forKey: SettingsKey.textExtractorService)
            default:
                break // Already migrated or valid
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(cameraManager)
                .onOpenURL { url in
                    print("📎 NotebookSaver received URL: \(url.path)")
                    print("📎 URL scheme: \(url.scheme ?? "none"), file extension: \(url.pathExtension)")
                    appState.processOpenedImage(url: url)
                }
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
