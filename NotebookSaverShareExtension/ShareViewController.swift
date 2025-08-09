import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let appGroupId = "group.com.daviddegner.NotebookSaver"
    private let sharedFolderName = "SharedImports"

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        processSharedItems()
    }

    private func processSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeExtension()
            return
        }

        for item in extensionItems {
            guard let providers = item.attachments else { continue }
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (item, error) in
                        guard let self = self else { return }
                        if let error = error {
                            print("ShareViewController: loadItem error: \(error.localizedDescription)")
                            self.completeExtension()
                            return
                        }
                        self.handleLoadedItem(item)
                    }
                    return // Only handle one image
                }
            }
        }

        // No suitable item found
        completeExtension()
    }

    private func handleLoadedItem(_ item: NSSecureCoding?) {
        var imageData: Data?

        if let url = item as? URL {
            imageData = try? Data(contentsOf: url)
        } else if let image = item as? UIImage {
            imageData = image.jpegData(compressionQuality: 0.9)
        } else if let data = item as? Data {
            imageData = data
        }

        guard let data = imageData else {
            completeExtension()
            return
        }

        // Save to shared container
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            completeExtension()
            return
        }
        let folderURL = containerURL.appendingPathComponent(sharedFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let filename = "shared_\(UUID().uuidString).jpg"
        let fileURL = folderURL.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("ShareViewController: Failed to write file: \(error.localizedDescription)")
            completeExtension()
            return
        }

        // Open main app to process
        if let openURL = URL(string: "notebooksaver://import?file=\(filename)") {
            extensionContext?.open(openURL, completionHandler: { [weak self] _ in
                self?.completeExtension()
            })
        } else {
            completeExtension()
        }
    }

    private func completeExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}