import Foundation
import UIKit
import Photos

final class SharedImportHandler {
    static let appGroupId = "group.com.daviddegner.NotebookSaver"
    static let sharedFolderName = "SharedImports"

    static func handleIncomingURL(_ url: URL) {
        guard url.scheme == "notebooksaver",
              url.host == "import",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let fileParam = components.queryItems?.first(where: { $0.name == "file" })?.value
        else {
            print("SharedImportHandler: URL not recognized: \(url.absoluteString)")
            return
        }

        Task {
            do {
                guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
                    print("SharedImportHandler: Could not access app group container")
                    return
                }
                let folderURL = containerURL.appendingPathComponent(sharedFolderName, isDirectory: true)
                let fileURL = folderURL.appendingPathComponent(fileParam)

                let data = try Data(contentsOf: fileURL)
                try await processSharedImageData(data)

                // Cleanup the imported file after processing
                try? FileManager.default.removeItem(at: fileURL)
            } catch {
                print("SharedImportHandler: Failed to process shared image: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Pipeline (mirror CameraView)

    private static func processSharedImageData(_ data: Data) async throws {
        guard let image = UIImage(data: data) else {
            throw CameraManager.CameraError.processingFailed("Could not create UIImage from shared data.")
        }

        async let _ = savePhotoIfNeeded(image: image)
        async let text = extractText(from: image)

        let extractedText = try await text
        try await sendToTargetApp(text: extractedText)
    }

    private static func extractText(from processedImage: UIImage) async throws -> String {
        let defaults = UserDefaults.standard
        let selectedServiceRaw = defaults.string(forKey: "textExtractorService") ?? TextExtractorType.gemini.rawValue
        var selectedService = TextExtractorType(rawValue: selectedServiceRaw) ?? .gemini

        if selectedService == .gemini {
            let apiKey = KeychainService.loadAPIKey()
            if apiKey?.isEmpty ?? true {
                selectedService = .vision
            }
        }

        let textExtractor: ImageTextExtractor = (selectedService == .gemini) ? GeminiService() : VisionService()
        return try await textExtractor.extractText(from: processedImage)
    }

    private static func savePhotoIfNeeded(image: UIImage) async throws -> URL? {
        let savePhotosEnabled = UserDefaults.standard.bool(forKey: "savePhotosEnabled")
        let photoFolder = UserDefaults.standard.string(forKey: "photoFolderName") ?? "notebook"
        let shouldSavePhoto = savePhotosEnabled && !photoFolder.isEmpty
        guard shouldSavePhoto else { return nil }

        do {
            guard let processedImageData = image.jpegData(compressionQuality: 0.9) else {
                throw CameraManager.CameraError.processingFailed("Could not encode processed image for saving.")
            }
            let localIdentifier = try await CameraManager(setupOnInit: false).savePhotoToAlbum(imageData: processedImageData, albumName: photoFolder)
            return CameraManager(setupOnInit: false).generatePhotoURL(for: localIdentifier)
        } catch {
            print("SharedImportHandler: Failed to save photo: \(error.localizedDescription)")
            return nil
        }
    }

    private static func sendToTargetApp(text: String) async throws {
        let draftsTag = UserDefaults.standard.string(forKey: "draftsTag") ?? "notebook"
        let addDraftTagEnabled = UserDefaults.standard.bool(forKey: "addDraftTagEnabled")

        var tagsToSend = [String]()
        if addDraftTagEnabled && !draftsTag.isEmpty {
            tagsToSend.append(draftsTag)
        }

        let uniqueTags = Set(tagsToSend)
        let combinedTags = uniqueTags.joined(separator: ",")

        if let draftsURL = URL(string: "drafts://"), await MainActor.run({ UIApplication.shared.canOpenURL(draftsURL) }) {
            let _ = try await DraftsHelper.createDraftAsync(with: text, tag: combinedTags)
        } else {
            await MainActor.run {
                SharingHelper.presentShareSheet(text: text)
            }
        }
    }
}