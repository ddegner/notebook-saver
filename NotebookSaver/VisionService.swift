import Foundation
import Vision
import UIKit // For UIImage
import CoreImage // Needed for preprocessing
enum VisionError: LocalizedError {
    // case imageConversionFailed // Replaced by PreprocessingError
    case requestHandlerFailed(Error)
    case noTextFound
    case visionRequestFailed(Error)
    // case preprocessingFailed(String) // Replaced by PreprocessingError
    case preprocessingError(PreprocessingError) // Wrap PreprocessingError

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

    // Removed reference to ImagePreprocessor as we'll handle UIImage/CGImage directly
    // private let imagePreprocessor = ImageProcessor()

    // Define keys for UserDefaults access (matching SettingsView)
    private enum StorageKeys {
        static let visionRecognitionLevel = "visionRecognitionLevel"
        static let visionUsesLanguageCorrection = "visionUsesLanguageCorrection"
    }

    // Reuse CIContext for efficiency, similar to Cloud service - Removed, context is in ImagePreprocessor
    // private let ciContext = CIContext()

    func extractText(from imageData: Data) async throws -> String {
        // Create UIImage from data and delegate to optimized method
        guard let uiImage = UIImage(data: imageData) else {
            throw PreprocessingError.invalidImageData
        }
        return try await extractText(from: uiImage)
    }
    
    // MARK: - Optimized method for pre-processed images
    func extractText(from processedImage: UIImage) async throws -> String {
        // 1. Get CGImage directly from processed UIImage
        guard let cgImage = processedImage.cgImage else {
            throw VisionError.preprocessingError(PreprocessingError.invalidImageData)
        }
        print("VisionService: Using pre-processed UIImage directly.")

        // 2. Create a Vision Request (VNRecognizeTextRequest)
        let textRecognitionRequest = VNRecognizeTextRequest { (_, error) in
            // This completion handler will be called on a background thread
            if let error = error {
                // This error is handled in the continuation below
                print("Vision internal request error: \(error)")
            }
        }

        // -- Apply settings from UserDefaults --
        let defaults = UserDefaults.standard

        // Recognition Level
        let levelString = defaults.string(forKey: StorageKeys.visionRecognitionLevel) ?? "accurate" // Default to accurate
        if levelString == "fast" {
            textRecognitionRequest.recognitionLevel = .fast
            print("VisionService: Using recognition level: fast")
        } else {
            textRecognitionRequest.recognitionLevel = .accurate
            print("VisionService: Using recognition level: accurate")
        }

        // Language Correction
        let useCorrection = defaults.bool(forKey: StorageKeys.visionUsesLanguageCorrection) // Defaults to false if key doesn't exist, but Settings sets a default
        textRecognitionRequest.usesLanguageCorrection = useCorrection
        print("VisionService: Using language correction: \(useCorrection)")
        // -- End Apply Settings --

        // 3. Create a Request Handler with the CGImage
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // 4. Perform the Request Asynchronously
        return try await withCheckedThrowingContinuation { continuation in
            do {
                print("Performing Vision text recognition...")
                try requestHandler.perform([textRecognitionRequest])
                print("Vision request performed.")

                // Process results
                guard let results = textRecognitionRequest.results, 
                      !results.isEmpty else {
                    print("Vision found no text observations.")
                    continuation.resume(throwing: VisionError.noTextFound)
                    return
                }
                print("Found \(results.count) text observations.")

                // Extract text
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
