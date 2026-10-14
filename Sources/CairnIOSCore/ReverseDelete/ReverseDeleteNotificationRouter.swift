import Foundation
import CairnCore

#if canImport(UserNotifications)
import UserNotifications

/// Opens the review sheet when the weekly reminder is tapped. cairn has
/// no other notifications today; if it gains some, merge their routing
/// here rather than installing a second delegate (iOS keeps only one).
public final class ReverseDeleteNotificationRouter: NSObject, UNUserNotificationCenterDelegate, Sendable {

    public static let shared = ReverseDeleteNotificationRouter()

    /// Hook: call once at launch, before the app finishes launching.
    public static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier == ServerTrashReminderScheduler.identifier else { return }
        await MainActor.run { ReverseDeleteController.shared.openReview() }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
#endif
