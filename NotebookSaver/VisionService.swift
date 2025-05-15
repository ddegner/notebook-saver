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

    // Reuse CIContext for efficiency, similar to GeminiService - Removed, context is in ImagePreprocessor
    // private let ciContext = CIContext()

    func extractText(from imageData: Data) async throws -> String {
        // 1. Prepare CGImage directly from input data
        let cgImage: CGImage
        do {
            // a. Create UIImage from original data
            guard let uiImage = UIImage(data: imageData) else {
                // Use the PreprocessingError enum directly or define a Vision-specific one
                throw PreprocessingError.invalidImageData // Reusing the enum from ImageProcessor for consistency
            }

            // b. Get CGImage from UIImage
            guard let imageToProcess = uiImage.cgImage else {
                // Throw an error if CGImage cannot be obtained
                throw VisionError.preprocessingError(PreprocessingError.invalidImageData) // Wrap in VisionError
            }
            cgImage = imageToProcess
            print("VisionService: Created CGImage directly from input imageData.")

        } catch let error as PreprocessingError {
            // Wrap PreprocessingError if thrown directly
            throw VisionError.preprocessingError(error)
        } catch {
            // Catch any other unexpected error during UIImage/CGImage creation
            throw VisionError.preprocessingError(PreprocessingError.invalidImageData) // Assuming failure means invalid data
        }

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
                guard let observations = textRecognitionRequest.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    print("Vision found no text observations.")
                    continuation.resume(throwing: VisionError.noTextFound)
                    return
                }
                print("Found \(observations.count) text observations.")

                // Extract text
                let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
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
