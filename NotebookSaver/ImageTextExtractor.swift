import Foundation
import UIKit

// Protocol defining the interface for extracting text from image data
protocol ImageTextExtractor {
    func extractText(from imageData: Data) async throws -> String
    func extractText(from imageData: Data, sessionId: UUID?) async throws -> String
    // New optimized method that accepts pre-processed UIImage
    func extractText(from processedImage: UIImage) async throws -> String
    func extractText(from processedImage: UIImage, sessionId: UUID?) async throws -> String
}

// Default implementations for backward compatibility
extension ImageTextExtractor {
    func extractText(from imageData: Data) async throws -> String {
        return try await extractText(from: imageData, sessionId: nil)
    }
    
    func extractText(from processedImage: UIImage) async throws -> String {
        return try await extractText(from: processedImage, sessionId: nil)
    }
}

// Enum to identify the different service types
enum TextExtractorType: String, CaseIterable, Identifiable {
    case gemini = "gemini"   // Stable identifier for cloud service
    case vision = "vision"   // Stable identifier for local service

    var id: String { self.rawValue }
    
    /// User-facing display name for the service
    var displayName: String {
        switch self {
        case .gemini: return "Cloud"
        case .vision: return "Local"
        }
    }
}
