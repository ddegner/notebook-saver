import UIKit

struct SharingHelper {
    @MainActor
    static func presentShareSheet(text: String) {
        let activityItems: [Any] = [text]

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            print("SharingHelper: Could not find root view controller to present share sheet.")
            return
        }

        let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)

        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceView = rootViewController.view
            popoverController.sourceRect = CGRect(
                x: rootViewController.view.bounds.midX,
                y: rootViewController.view.bounds.midY,
                width: 0,
                height: 0
            )
            popoverController.permittedArrowDirections = []
        }

        rootViewController.present(activityViewController, animated: true, completion: nil)
    }
}