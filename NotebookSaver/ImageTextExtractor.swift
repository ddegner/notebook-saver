import Foundation

// Protocol defining the interface for extracting text from image data
protocol ImageTextExtractor {
    func extractText(from imageData: Data) async throws -> String
}

// Enum to identify the different service types
enum TextExtractorType: String, CaseIterable, Identifiable {
    case gemini = "Cloud"
    case vision = "Local"

    var id: String { self.rawValue }
}
