import Foundation
import CairnCore

#if canImport(UserNotifications)
import UserNotifications

/// The weekly "photos trashed on Immich are still on this iPhone" local
/// notification. One pending request under a fixed identifier: each
/// check replaces it (count > 0) or removes it (count == 0), so at most
/// one reminder per week and none when nothing is waiting. Timing rules
/// live in `ServerTrashCheckPolicy`.
public enum ServerTrashReminderScheduler {

    public static let identifier = "app.cairn.serverTrash.weekly"

    /// Shows the iOS permission prompt the first time; later calls
    /// return the stored answer without prompting.
    @discardableResult
    public static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge])) ?? false
    }

    public static func update(pendingCount: Int, weekday: Int, minuteOfDay: Int) async {
        let center = UNUserNotificationCenter.current()
        guard pendingCount > 0 else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Immich trash"
        content.body = ServerTrashCheckPolicy.reminderBody(count: pendingCount)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: ServerTrashCheckPolicy.reminderComponents(weekday: weekday, minuteOfDay: minuteOfDay),
            repeats: false
        )
        // Same identifier replaces the pending request.
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    public static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
#endif
