import Foundation

/// When the reverse-direction check runs during sync, and when its
/// weekly reminder fires. Pure so the timing rules are testable.
///
/// The check piggybacks on whatever sync runs (foreground, background,
/// Shortcut) at most about once a day, and looks back over Immich's
/// default 30-day trash retention, so even a sync every few weeks
/// catches everything. The reminder is a single non-repeating local
/// notification that each check rewrites (count > 0) or removes
/// (count == 0); iOS delivers it at the next matching weekday + time.
public enum ServerTrashCheckPolicy {

    /// Immich's default trash retention.
    public static let lookbackDays = 30

    /// Reminder default: Sunday (`Calendar` weekday 1) at 10:00.
    public static let defaultWeekday = 1
    public static let defaultMinuteOfDay = 600

    /// Slightly under a day so a daily background slot that drifts
    /// earlier doesn't skip a day.
    public static let minInterval: TimeInterval = 20 * 3600

    public static func isDue(lastCheckedAt: Date?, now: Date, minInterval: TimeInterval = minInterval) -> Bool {
        guard let lastCheckedAt else { return true }
        // A clock moved backwards also counts as due.
        return now.timeIntervalSince(lastCheckedAt) >= minInterval || now < lastCheckedAt
    }

    /// Date components for the reminder trigger. Out-of-range settings
    /// are clamped rather than rejected.
    public static func reminderComponents(weekday: Int, minuteOfDay: Int) -> DateComponents {
        let day = min(max(weekday, 1), 7)
        let minutes = min(max(minuteOfDay, 0), 24 * 60 - 1)
        var c = DateComponents()
        c.weekday = day
        c.hour = minutes / 60
        c.minute = minutes % 60
        return c
    }

    /// Next date the reminder would fire, strictly after `now`. Used for
    /// the "Next reminder" label; the notification trigger computes the
    /// same thing on its own.
    public static func nextReminder(after now: Date, weekday: Int, minuteOfDay: Int, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: now,
            matching: reminderComponents(weekday: weekday, minuteOfDay: minuteOfDay),
            matchingPolicy: .nextTime
        )
    }

    /// Notification body for `count` waiting photos.
    public static func reminderBody(count: Int) -> String {
        count == 1
            ? "1 photo trashed on Immich is still on this iPhone. Tap to review."
            : "\(count) photos trashed on Immich are still on this iPhone. Tap to review."
    }
}
