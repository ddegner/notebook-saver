import Foundation
import UserNotifications
import UIKit

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private override init() { super.init() }

    private let draftReadyCategoryId = "DRAFT_READY_CATEGORY"
    private let pendingDraftIdKey = "pendingDraftId"

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Register categories
        let category = UNNotificationCategory(
            identifier: draftReadyCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])

        // Request authorization if not already granted
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus != .authorized else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error = error {
                    print("Notification authorization error: \(error)")
                } else {
                    print("Notification authorization granted: \(granted)")
                }
            }
        }
    }

    func scheduleDraftReadyNotification(pendingDraftId: String, previewText: String) {
        let content = UNMutableNotificationContent()
        content.title = "Page ready"
        content.body = previewText.isEmpty ? "Tap to create a new draft in Drafts" : previewText
        content.sound = .default
        content.categoryIdentifier = draftReadyCategoryId
        content.userInfo = [pendingDraftIdKey: pendingDraftId]

        let request = UNNotificationRequest(
            identifier: "draftReady_\(pendingDraftId)",
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule draft ready notification: \(error)")
            } else {
                print("Scheduled draft ready notification for id: \(pendingDraftId)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if response.notification.request.content.categoryIdentifier == draftReadyCategoryId,
           let pendingId = userInfo[pendingDraftIdKey] as? String {
            Task { @MainActor in
                await DraftsHelper.createPendingDraft(by: pendingId)
                completionHandler()
            }
            return
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show banner if app is in foreground so user can still tap it
        if notification.request.content.categoryIdentifier == draftReadyCategoryId {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.banner, .sound])
        }
    }
}