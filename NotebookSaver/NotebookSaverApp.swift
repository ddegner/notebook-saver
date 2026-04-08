import SwiftUI

@main
struct NotebookSaverApp: App {
    @StateObject private var appState = AppStateManager()
    @StateObject private var cameraManager = CameraManager()
    @State private var didRunAutomationImageInput = false
    @AppStorage(SettingsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register default values for all settings
        let defaults: [String: Any] = [
            SettingsKey.selectedModelId: "gemini-3.1-flash-lite-preview",
            SettingsKey.textExtractorService: "vision",
            SettingsKey.savePhotosEnabled: false,
            SettingsKey.addDraftTagEnabled: true,
            SettingsKey.draftsTag: "notebook",
            SettingsKey.photoFolderName: "notebook",
            SettingsKey.visionRecognitionLevel: "accurate",
            SettingsKey.visionUsesLanguageCorrection: true,
            SettingsKey.thinkingLevel: GeminiThinkingLevel.none.rawValue,
            SettingsKey.userMessagePrompt: GeminiService.defaultUserMessagePrompt,
            SettingsKey.geminiPhotoTokenBudget: GeminiPhotoTokenBudget.medium.rawValue,
            SettingsKey.scanMode: ScanMode.fast.rawValue,
            SettingsKey.useCustomSettings: false
        ]
        UserDefaults.standard.register(defaults: defaults)
        SharedDefaults.suite.register(defaults: defaults)

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
                    if url.scheme == "notebooksaver", url.host == "process-shared" {
                        processPendingSharedImage()
                    } else {
                        appState.processOpenedImage(url: url)
                    }
                }
                .sheet(isPresented: $appState.showOnboarding) {
                    OnboardingView(isOnboarding: $appState.showOnboarding)
                        .environmentObject(appState)
                }
                .onAppear {
                    TextExtractionPipeline.syncSettingsToSharedSuite()
                    if !hasCompletedOnboarding {
                        // If an API key already exists (e.g. from a previous install via Keychain),
                        // skip onboarding automatically.
                        if KeychainService.loadAPIKey() != nil {
                            hasCompletedOnboarding = true
                            // API key present — default to Gemini (only if no service was explicitly chosen)
                            if UserDefaults.standard.object(forKey: SettingsKey.textExtractorService) == nil {
                                UserDefaults.standard.set("gemini", forKey: SettingsKey.textExtractorService)
                                TextExtractionPipeline.syncSettingsToSharedSuite()
                            }
                        } else {
                            appState.presentOnboarding()
                        }
                    }
                    runAutomationImageInputIfConfigured()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        TextExtractionPipeline.syncSettingsToSharedSuite()
                        Task { await DraftsHelper.createPendingDrafts() }
                        processPendingSharedImage()
                    }
                }
        }
    }

    private func processPendingSharedImage() {
        guard let path = SharedDefaults.suite.string(forKey: "pendingSharedImagePath") else { return }
        SharedDefaults.suite.removeObject(forKey: "pendingSharedImagePath")
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        appState.processOpenedImage(url: fileURL)
    }

    private func runAutomationImageInputIfConfigured() {
#if DEBUG
        guard !didRunAutomationImageInput else { return }
        guard let path = ProcessInfo.processInfo.environment["NOTEBOOK_AUTOMATION_IMAGE_PATH"],
              !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        didRunAutomationImageInput = true
        appState.processOpenedImage(url: url)
#endif
    }
}
