import Foundation
import CoreImage
import UIKit // For UIImage
import ImageIO // Added ImageIO for HEIC encoding
import UniformTypeIdentifiers // Added for UTType

// Define specific errors for preprocessing
enum PreprocessingError: LocalizedError {
    case invalidImageData
    case encodingFailed(Error?) // Added for generic encoding errors
    case resizeFailed // Added error for resizing issues

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Could not create UIImage from the provided data."
        case .encodingFailed(let underlyingError):
            guard let error = underlyingError else {
                return "Could not create HEIC data from UIImage."
            }
            return "Could not create HEIC data from UIImage: \(error.localizedDescription)"
        case .resizeFailed:
             return "Failed to resize the image."
        }
    }
}

// Utility struct for image processing
struct ImageProcessor {

    // Reusable CIContext might still be useful for other things, keep for now.
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

        // Calculate scale factors for both dimensions
        let scaleX = targetWidth / originalSize.width
        let scaleY = targetHeight / originalSize.height

        // Apply Lanczos scale transform filter
        guard let resizeFilter = CIFilter(name: "CILanczosScaleTransform") else {
            print("ImageProcessor: Error: CILanczosScaleTransform filter could not be created.")
            throw PreprocessingError.resizeFailed
        }
        
        resizeFilter.setValue(enhancedCIImage, forKey: kCIInputImageKey)
        resizeFilter.setValue(Float(scaleX), forKey: kCIInputScaleKey)
        resizeFilter.setValue(Float(scaleY), forKey: kCIInputAspectRatioKey)

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

    // Function to resize a UIImage using Core Image (potentially faster) - kept for backward compatibility
    func resizeImage(_ image: UIImage, maxDimension: CGFloat) throws -> UIImage {
        guard let originalCIImage = CIImage(image: image) else {
             throw PreprocessingError.invalidImageData // Or a more specific CIImage creation error
         }

        let originalSize = originalCIImage.extent.size
        guard max(originalSize.width, originalSize.height) > 0 else {
             print("Warning: Attempted to resize an image with zero dimensions.")
             return image // Return original if invalid
         }

        // Determine if resize is needed
        guard max(originalSize.width, originalSize.height) > maxDimension else {
            print("ImageProcessor (Core Image): Image size (\(originalSize)) is within limit (\(maxDimension)), no resize needed.")
            return image // No resize needed, return original UIImage
        }

        // Calculate scale
        let scale = maxDimension / max(originalSize.width, originalSize.height)

        // Apply Lanczos scale transform filter
        guard let resizeFilter = CIFilter(name: "CILanczosScaleTransform") else {
            print("ImageProcessor (Core Image): Error: CILanczosScaleTransform filter could not be created.")
            throw PreprocessingError.resizeFailed // Or a more specific error like .filterCreationFailed if defined
        }
        resizeFilter.setValue(originalCIImage, forKey: kCIInputImageKey)
        resizeFilter.setValue(Float(scale), forKey: kCIInputScaleKey)
        resizeFilter.setValue(1.0, forKey: kCIInputAspectRatioKey) // Preserve aspect ratio

        guard let resizedCIImage = resizeFilter.outputImage else {
            print("ImageProcessor (Core Image): Warning: Resize filter failed to produce output.")
            throw PreprocessingError.resizeFailed
        }

        // Convert resized CIImage back to CGImage, then UIImage
        guard let resizedCGImage = ciContext.createCGImage(resizedCIImage, from: resizedCIImage.extent) else {
             print("ImageProcessor (Core Image): Failed to create CGImage from resized CIImage.")
             throw PreprocessingError.resizeFailed // Or a more specific error
         }

        let finalUIImage = UIImage(cgImage: resizedCGImage)
        print("ImageProcessor (Core Image): Resized image from \(originalSize) to \(finalUIImage.size)")
        return finalUIImage
    }

    // Convert UIImage to HEIC Data
    func encodeToHEICData(_ image: UIImage, compressionQuality: CGFloat = 0.7) throws -> Data {
        guard let cgImage = image.cgImage else {
            print("ImageProcessor: Failed to get CGImage from UIImage.")
            throw PreprocessingError.invalidImageData // Or a more specific error
        }

        let imageData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(imageData, UTType.heic.identifier as CFString, 1, nil) else {
            print("ImageProcessor: Failed to create CGImageDestination for HEIC.")
            throw PreprocessingError.encodingFailed(nil) // More specific error could be defined
        }

        let properties = [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary

        CGImageDestinationAddImage(destination, cgImage, properties)

        if CGImageDestinationFinalize(destination) {
            print("ImageProcessor: Encoded UIImage to HEIC data (\(imageData.length) bytes) with quality \(compressionQuality).")
            return imageData as Data
        } else {
            print("ImageProcessor: Failed to finalize HEIC encoding.")
            // Attempt to get an error from the destination if possible, though CGImageDestinationFinalize doesn't directly provide one.
            // For now, throw a generic encoding failed error.
            throw PreprocessingError.encodingFailed(nil) // Consider adding more error details if possible
        }
    }
}
