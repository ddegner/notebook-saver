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

    // Define keys for UserDefaults access (matching SettingsView)
    private enum StorageKeys {
        static let visionRecognitionLevel = "visionRecognitionLevel"
        static let visionUsesLanguageCorrection = "visionUsesLanguageCorrection"
    }

    func extractText(from imageData: Data, sessionId: UUID? = nil) async throws -> String {
        // Create UIImage from data and delegate to optimized method
        guard let uiImage = UIImage(data: imageData) else {
            throw PreprocessingError.invalidImageData
        }
        return try await extractText(from: uiImage, sessionId: sessionId)
    }
    
    // MARK: - Optimized method for pre-processed images
    func extractText(from processedImage: UIImage, sessionId: UUID? = nil) async throws -> String {
        // 1. Get CGImage directly from processed UIImage
        guard let cgImage = processedImage.cgImage else {
            throw VisionError.preprocessingError(PreprocessingError.invalidImageData)
        }
        print("VisionService: Using pre-processed UIImage directly.")

        // Capture image metadata for performance logging
        let imageData = processedImage.jpegData(compressionQuality: 1.0) ?? Data()
        let fileSizeBytes = imageData.count
        
        // Get actual pixel dimensions from CGImage, not logical UIImage size
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        
        // Create image metadata (Vision uses the processed image directly, so original = processed)
        let imageMetadata = ImageMetadata(
            originalWidth: CGFloat(pixelWidth),
            originalHeight: CGFloat(pixelHeight),
            processedWidth: CGFloat(pixelWidth),
            processedHeight: CGFloat(pixelHeight),
            originalFileSizeBytes: fileSizeBytes,
            processedFileSizeBytes: fileSizeBytes,
            compressionQuality: nil, // Vision doesn't compress
            imageFormat: "UIImage"
        )

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
        
        // Create model info for performance logging with image metadata
        let modelInfo = ModelInfo(
            serviceName: "Vision",
            modelName: "Apple Vision",
            configuration: [
                "recognition_level": levelString,
                "language_correction": String(useCorrection)
            ],
            imageMetadata: imageMetadata
        )

        // 3. Create a Request Handler with the CGImage
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // 4. Perform the Request Asynchronously
        if let sessionId = sessionId {
            // Use performance logger for timing
            return try await PerformanceLogger.shared.measureOperation(
                "Vision Text Recognition (\(levelString))",
                sessionId: sessionId,
                modelInfo: modelInfo
            ) {
                try await withCheckedThrowingContinuation { continuation in
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
        } else {
            // Fallback without performance logging when no session provided
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
}
