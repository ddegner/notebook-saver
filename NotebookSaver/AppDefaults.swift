import Foundation

/// Centralized app defaults to ensure consistency across the app
enum AppDefaults {
    /// Default text extractor service - set to Vision (Local) since it works without setup
    /// The onboarding flow will change this to Gemini when user provides API key
    static let textExtractorService = TextExtractorType.vision.rawValue
}