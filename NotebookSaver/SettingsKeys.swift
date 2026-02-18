import Foundation

/// Centralized UserDefaults keys used throughout the app
/// This eliminates duplication of key strings across multiple files
enum SettingsKey {
    // MARK: - AI Settings
    static let selectedModelId = "selectedModelId"
    static let userPrompt = "userPrompt"
    static let apiEndpointUrlString = "apiEndpointUrlString"
    static let thinkingEnabled = "thinkingEnabled"
    static let textExtractorService = "textExtractorService"
    static let geminiPhotoTokenBudget = "geminiPhotoTokenBudget"
    
    // MARK: - Vision Settings
    static let visionRecognitionLevel = "visionRecognitionLevel"
    static let visionUsesLanguageCorrection = "visionUsesLanguageCorrection"
    
    // MARK: - General Settings
    static let draftsTag = "draftsTag"
    static let photoFolderName = "photoFolderName"
    static let savePhotosEnabled = "savePhotosEnabled"
    static let addDraftTagEnabled = "addDraftTagEnabled"
    
    // MARK: - Model Cache
    static let cachedGeminiModels = "cachedGeminiModels"
    static let hasInitiallyFetchedModels = "hasInitiallyFetchedModels"
    
    // MARK: - App State
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let pendingDrafts = "pendingDrafts"
}
