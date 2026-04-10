import Foundation
import UIKit

/// Single source of truth for extracting text from an image.
/// Used by both the main app (CameraView) and the Share Extension.
/// Reads settings from `SharedDefaults.suite` so it works in both contexts.
enum TextExtractionPipeline {

    /// Extract text from a UIImage using the user's configured service.
    /// Falls back to Vision if the Gemini API key is missing.
    /// - Parameters:
    ///   - image: The (optionally pre-processed) image to extract text from.
    ///   - sessionId: Optional performance-logging session (pass `nil` from the share extension).
    static func extractText(from image: UIImage, sessionId: UUID? = nil) async throws -> String {
        let defaults = SharedDefaults.suite
        let serviceRaw = defaults.string(forKey: SettingsKey.textExtractorService)
            ?? TextExtractorType.vision.rawValue
        var service = TextExtractorType(rawValue: serviceRaw) ?? .vision

        // Fall back to Vision when no API key is available
        if service == .gemini {
            let apiKey = KeychainService.loadAPIKey()
            if apiKey?.isEmpty ?? true {
                #if DEBUG
                print("TextExtractionPipeline: Gemini selected but API key missing, falling back to Vision")
                #endif
                service = .vision
            }
        }

        #if DEBUG
        print("TextExtractionPipeline: Using \(service.displayName) service")
        #endif

        let extractor: ImageTextExtractor
        switch service {
        case .gemini:
            extractor = GeminiService()
        case .vision:
            extractor = VisionService()
        }

        return try await extractor.extractText(from: image, sessionId: sessionId)
    }

    /// Streaming variant — yields text chunks as they arrive from the API.
    /// Falls back to a single-yield stream for VisionService.
    static func extractTextStream(from image: UIImage, sessionId: UUID? = nil) async -> AsyncThrowingStream<String, Error> {
        let defaults = SharedDefaults.suite
        let serviceRaw = defaults.string(forKey: SettingsKey.textExtractorService)
            ?? TextExtractorType.vision.rawValue
        var service = TextExtractorType(rawValue: serviceRaw) ?? .vision

        if service == .gemini {
            let apiKey = KeychainService.loadAPIKey()
            if apiKey?.isEmpty ?? true {
                #if DEBUG
                print("TextExtractionPipeline: Gemini selected but API key missing, falling back to Vision")
                #endif
                service = .vision
            }
        }

        #if DEBUG
        print("TextExtractionPipeline (stream): Using \(service.displayName) service")
        #endif

        let extractor: ImageTextExtractor
        switch service {
        case .gemini:
            extractor = GeminiService()
        case .vision:
            extractor = VisionService()
        }

        return await extractor.extractTextStream(from: image, sessionId: sessionId)
    }

    // MARK: - Settings Sync

    /// Keys that need to be readable by the share extension.
    private static let syncedKeys: [String] = [
        SettingsKey.textExtractorService,
        SettingsKey.selectedModelId,
        SettingsKey.scanMode,
        SettingsKey.useCustomSettings,
        SettingsKey.userPrompt,
        SettingsKey.userMessagePrompt,
        SettingsKey.apiEndpointUrlString,
        SettingsKey.thinkingLevel,
        SettingsKey.geminiPhotoTokenBudget,
        SettingsKey.visionRecognitionLevel,
        SettingsKey.visionUsesLanguageCorrection,
        SettingsKey.draftsTag,
        SettingsKey.addDraftTagEnabled
    ]

    /// Copies relevant settings from UserDefaults.standard to the shared
    /// App Group suite. Call this from the main app (e.g. on launch / foreground)
    /// so the share extension always has up-to-date configuration.
    static func syncSettingsToSharedSuite() {
        let source = UserDefaults.standard
        let destination = SharedDefaults.suite
        for key in syncedKeys {
            if let value = source.object(forKey: key) {
                destination.set(value, forKey: key)
            }
        }
    }
}

// MARK: - Backward compatibility alias
/// Convenience alias so the share extension can use either name.
typealias ShareExtensionPipeline = TextExtractionPipeline
