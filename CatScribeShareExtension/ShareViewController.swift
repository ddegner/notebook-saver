import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Entry point for the Cat Scribe share extension.
/// Bridges into SwiftUI via UIHostingController. After the image is saved to
/// the App Group container, this controller opens Cat Scribe via URL scheme and
/// dismisses the extension inside the completion handler so iOS processes the
/// URL open before tearing down the extension process.
class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(
            rootView: ShareView(
                extensionContext: extensionContext,
                onSaved: { [weak self] in self?.openAndDismiss() }
            )
        )

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        hostingController.didMove(toParent: self)
    }

    /// Called after the image is successfully saved to the App Group container.
    /// Calls completeRequest inside the open() completion handler so the extension
    /// process stays alive until iOS has actually switched to Cat Scribe.
    /// Without this, the process tears down before iOS processes the URL open.
    private func openAndDismiss() {
        guard let url = URL(string: "notebooksaver://process-shared"),
              let ctx = extensionContext else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        ctx.open(url) { _ in
            ctx.completeRequest(returningItems: nil)
        }
    }
}
