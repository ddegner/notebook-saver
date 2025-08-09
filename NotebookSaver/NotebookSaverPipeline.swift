import Foundation
import UIKit

struct NotebookSaverPipeline {
    static func processImage(_ image: UIImage) async throws -> String {
        let defaults = SharedDefaults.suite
        let selectedServiceRaw = defaults.string(forKey: "textExtractorService") ?? TextExtractorType.cloud.rawValue
        var selectedService = TextExtractorType(rawValue: selectedServiceRaw) ?? .cloud

        if selectedService == .cloud {
            let apiKey = KeychainService.loadAPIKey()
            if apiKey?.isEmpty ?? true {
                selectedService = .vision
            }
        }

        let textExtractor: ImageTextExtractor
        switch selectedService {
        case .cloud:
            textExtractor = GeminiService()
        case .vision:
            textExtractor = VisionService()
        }

        return try await textExtractor.extractText(from: image)
    }
}