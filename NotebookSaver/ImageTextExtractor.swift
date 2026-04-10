import Foundation
import UIKit

// Protocol defining the interface for extracting text from image data
protocol ImageTextExtractor {
    func extractText(from imageData: Data) async throws -> String
    func extractText(from imageData: Data, sessionId: UUID?) async throws -> String
    // New optimized method that accepts pre-processed UIImage
    func extractText(from processedImage: UIImage) async throws -> String
    func extractText(from processedImage: UIImage, sessionId: UUID?) async throws -> String
    // Streaming variant — must be a protocol requirement (not just extension)
    // so GeminiService's override is dispatched dynamically.
    func extractTextStream(from processedImage: UIImage, sessionId: UUID?) async -> AsyncThrowingStream<String, Error>
}

// Default implementations for backward compatibility
extension ImageTextExtractor {
    func extractText(from imageData: Data) async throws -> String {
        return try await extractText(from: imageData, sessionId: nil)
    }

    func extractText(from processedImage: UIImage) async throws -> String {
        return try await extractText(from: processedImage, sessionId: nil)
    }

    /// Default streaming implementation: wraps the non-streaming call into a single-element stream.
    /// GeminiService overrides this with real SSE streaming.
    func extractTextStream(from processedImage: UIImage, sessionId: UUID?) async -> AsyncThrowingStream<String, Error> {
        // Perform the extraction eagerly, then wrap the result in a stream.
        // This avoids capturing `self` in a @Sendable closure.
        do {
            let text = try await extractText(from: processedImage, sessionId: sessionId)
            return AsyncThrowingStream { continuation in
                continuation.yield(text)
                continuation.finish()
            }
        } catch {
            let capturedError = error
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: capturedError)
            }
        }
    }
}

// Enum to identify the different service types
enum TextExtractorType: String, CaseIterable, Identifiable {
    case gemini = "gemini"         // Stable identifier for cloud service
    case vision = "vision"         // Stable identifier for local service

    var id: String { self.rawValue }

    /// User-facing display name for the service
    var displayName: String {
        switch self {
        case .gemini: return "Cloud"
        case .vision: return "Apple OCR"
        }
    }
}
