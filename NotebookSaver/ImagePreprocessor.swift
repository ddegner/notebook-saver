import Foundation
import CoreImage
import UIKit // For UIImage

// Define specific errors for preprocessing
enum PreprocessingError: LocalizedError {
    case invalidImageData
    case encodingFailed(Error?)
    case resizeFailed // Added error for resizing issues

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Could not create UIImage from the provided data."
        case .encodingFailed(let underlyingError):
            guard let error = underlyingError else {
                return "Could not encode image data."
            }
            return "Could not encode image data: \(error.localizedDescription)"
        case .resizeFailed:
             return "Failed to resize the image."
        }
    }
}

struct ImageProcessor {
    private let ciContext = CIContext()

    // Function to resize a UIImage to specific dimensions with contrast enhancement
    func resizeImageToDimensions(_ image: UIImage, targetWidth: CGFloat, targetHeight: CGFloat) throws -> UIImage {
        guard let originalCIImage = CIImage(image: image) else {
            throw PreprocessingError.invalidImageData
        }

        let originalSize = originalCIImage.extent.size
        guard max(originalSize.width, originalSize.height) > 0 else {
            print("Warning: Attempted to resize an image with zero dimensions.")
            return image
        }

        // Apply contrast enhancement first
        guard let contrastFilter = CIFilter(name: "CIColorControls") else {
            print("ImageProcessor: Error: CIColorControls filter could not be created.")
            throw PreprocessingError.resizeFailed
        }
        
        contrastFilter.setValue(originalCIImage, forKey: kCIInputImageKey)
        contrastFilter.setValue(1.2, forKey: kCIInputContrastKey) // Increase contrast by 20%
        contrastFilter.setValue(0.0, forKey: kCIInputBrightnessKey) // Keep brightness neutral
        contrastFilter.setValue(1.0, forKey: kCIInputSaturationKey) // Keep saturation neutral
        
        guard let enhancedCIImage = contrastFilter.outputImage else {
            print("ImageProcessor: Warning: Contrast filter failed to produce output.")
            throw PreprocessingError.resizeFailed
        }

        // Calculate uniform scale to fit within the target box while preserving aspect ratio
        let scale = min(targetWidth / originalSize.width, targetHeight / originalSize.height)
        // Apply Lanczos scale transform with aspect ratio 1.0 to preserve AR
        guard let resizeFilter = CIFilter(name: "CILanczosScaleTransform") else {
            print("ImageProcessor: Error: CILanczosScaleTransform filter could not be created.")
            throw PreprocessingError.resizeFailed
        }
        
        resizeFilter.setValue(enhancedCIImage, forKey: kCIInputImageKey)
        resizeFilter.setValue(Float(scale), forKey: kCIInputScaleKey)
        resizeFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)

        guard let resizedCIImage = resizeFilter.outputImage else {
            print("ImageProcessor: Warning: Resize filter failed to produce output.")
            throw PreprocessingError.resizeFailed
        }

        // Convert resized CIImage back to CGImage, then UIImage
        guard let resizedCGImage = ciContext.createCGImage(resizedCIImage, from: resizedCIImage.extent) else {
            print("ImageProcessor: Failed to create CGImage from resized CIImage.")
            throw PreprocessingError.resizeFailed
        }

        let finalUIImage = UIImage(cgImage: resizedCGImage)
        print("ImageProcessor: Resized and enhanced image from \(originalSize) to \(finalUIImage.size) with increased contrast")
        return finalUIImage
    }
}
