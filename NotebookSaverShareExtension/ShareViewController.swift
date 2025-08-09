import UIKit
import Social
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        loadFirstImageData { data in
            let root = UIHostingController(rootView: ShareView(imageData: data))
            self.addChild(root)
            root.view.frame = self.view.bounds
            self.view.addSubview(root.view)
            root.didMove(toParent: self)
        }
    }

    private func loadFirstImageData(completion: @escaping (Data) -> Void) {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = extensionItem.attachments else {
            completion(Data())
            return
        }

        let imageTypes: [UTType] = [.image, .png, .jpeg, .heic]

        for provider in providers {
            for type in imageTypes {
                if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                    provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                        if let url = item as? URL, let data = try? Data(contentsOf: url) {
                            DispatchQueue.main.async { completion(data) }
                        } else if let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.95) {
                            DispatchQueue.main.async { completion(data) }
                        }
                    }
                    return
                }
            }
        }

        completion(Data())
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.extensionContext?.completeRequest(returningItems: nil)
    }
}