import Foundation

enum ImageProcessingMode: String, CaseIterable, Identifiable {
    case none = "None"
    case optimized = "Optimized"
    case appleIntelligence = "Apple Intelligence"

    var id: String { rawValue }
}