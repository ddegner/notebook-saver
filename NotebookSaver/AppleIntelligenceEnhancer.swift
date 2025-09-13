import Foundation
import UIKit
import CoreImage

enum AppleIntelligenceSupport {
    static var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            #if canImport(FoundationModels)
            return true
            #else
            return false
            #endif
        }
        return false
    }
}

struct AppleIntelligenceEnhancer {
    static func enhance(image: UIImage) async -> UIImage {
        if #available(iOS 26.0, *) {
            #if canImport(FoundationModels)
            // NOTE: Replace this block with real Foundation Models integration when SDK is available.
            // For now, we keep behavior identical to fallback to preserve OCR fidelity.
            return fallbackEnhance(image)
            #else
            return fallbackEnhance(image)
            #endif
        } else {
            return fallbackEnhance(image)
        }
    }

    private static func fallbackEnhance(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        // Mild exposure increase
        let exposure = CIFilter(name: "CIExposureAdjust")
        exposure?.setValue(ciImage, forKey: kCIInputImageKey)
        exposure?.setValue(0.25, forKey: kCIInputEVKey)
        let exposureOutput = exposure?.outputImage ?? ciImage

        // Slight contrast bump, reduced saturation for text clarity
        let controls = CIFilter(name: "CIColorControls")
        controls?.setValue(exposureOutput, forKey: kCIInputImageKey)
        controls?.setValue(1.05, forKey: kCIInputContrastKey)
        controls?.setValue(0.0, forKey: kCIInputSaturationKey)
        let finalOutput = controls?.outputImage ?? exposureOutput

        let context = CIContext()
        if let cg = context.createCGImage(finalOutput, from: finalOutput.extent) {
            return UIImage(cgImage: cg)
        }
        return image
    }
}