import Foundation
import Vision
import UIKit // For UIImage
import CoreImage // Needed for preprocessing

enum VisionError: LocalizedError {
    case requestHandlerFailed(Error)
    case noTextFound
    case visionRequestFailed(Error)
    case preprocessingError(PreprocessingError)

    var errorDescription: String? {
        switch self {
        case .requestHandlerFailed(let error):
            return "Vision request handler failed: \(error.localizedDescription)"
        case .noTextFound:
            return "Vision did not recognize any text in the image."
        case .visionRequestFailed(let error):
            return "Vision text recognition request failed: \(error.localizedDescription)"
        case .preprocessingError(let error):
            return "Image preprocessing failed: \(error.localizedDescription)"
        }
    }
}

class VisionService: ImageTextExtractor {
    private enum StorageKeys {
        static let visionRecognitionLevel = "visionRecognitionLevel"
        static let visionUsesLanguageCorrection = "visionUsesLanguageCorrection"
    }

    // MARK: - Optimized method for pre-processed images
    func extractText(from processedImage: UIImage) async throws -> String {
        guard let cgImage = processedImage.cgImage else {
            throw VisionError.preprocessingError(PreprocessingError.invalidImageData)
        }
        print("VisionService: Using pre-processed UIImage directly.")

        let textRecognitionRequest = VNRecognizeTextRequest { (_, error) in
            if let error = error { print("Vision internal request error: \(error)") }
        }

        let defaults = SharedDefaults.suite
        let levelString = defaults.string(forKey: StorageKeys.visionRecognitionLevel) ?? "accurate"
        textRecognitionRequest.recognitionLevel = (levelString == "fast") ? .fast : .accurate
        print("VisionService: Using recognition level: \(textRecognitionRequest.recognitionLevel == .fast ? "fast" : "accurate")")

        let useCorrection = defaults.bool(forKey: StorageKeys.visionUsesLanguageCorrection)
        textRecognitionRequest.usesLanguageCorrection = useCorrection
        print("VisionService: Using language correction: \(useCorrection)")

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        return try await withCheckedThrowingContinuation { continuation in
            do {
                print("Performing Vision text recognition...")
                try requestHandler.perform([textRecognitionRequest])
                print("Vision request performed.")

                guard let results = textRecognitionRequest.results, !results.isEmpty else {
                    print("Vision found no text observations.")
                    continuation.resume(throwing: VisionError.noTextFound)
                    return
                }

                let recognizedStrings = results.compactMap { $0.topCandidates(1).first?.string }
                let joinedText = recognizedStrings.joined(separator: "\n")
                print("Extracted text successfully.")
                continuation.resume(returning: joinedText)
            } catch let handlerError {
                print("Vision request handler failed: \(handlerError)")
                continuation.resume(throwing: VisionError.requestHandlerFailed(handlerError))
            }
        }
    }
}
