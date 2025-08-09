import AppIntents
import UIKit

struct ProcessPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "Process Photo"
    static var description = IntentDescription("Process a photo through NotebookSaver using current settings.")

    @Parameter(title: "Photo")
    var photo: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Process \(.photo)")
    }

    func perform() async throws -> some IntentResult {
        guard let data = try? Data(contentsOf: photo.fileURL),
              let image = UIImage(data: data) else {
            throw NSError(domain: "ProcessPhotoIntent", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }
        let text = try await NotebookSaverPipeline.processImage(image)
        return .result(value: text)
    }
}