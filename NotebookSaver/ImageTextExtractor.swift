import Foundation
import UIKit

// Protocol defining the interface for extracting text from image data
protocol ImageTextExtractor {
    func extractText(from imageData: Data) async throws -> String
    // New optimized method that accepts pre-processed UIImage
    func extractText(from processedImage: UIImage) async throws -> String
}

// Enum to identify the different service types
enum TextExtractorType: String, CaseIterable, Identifiable {
    case cloud = "Cloud"
    case vision = "Local"

    var id: String { self.rawValue }
}
