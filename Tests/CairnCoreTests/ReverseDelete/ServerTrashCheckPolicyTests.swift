import Foundation
import Testing
@testable import CairnCore

@Suite("ServerTrashCheckPolicy")
struct ServerTrashCheckPolicyTests {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test("never checked → due")
    func dueWhenNeverChecked() {
        #expect(ServerTrashCheckPolicy.isDue(lastCheckedAt: nil, now: Date()))
    }

    @Test("checked an hour ago → not due; 21 hours ago → due")
    func dueAfterInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(!ServerTrashCheckPolicy.isDue(lastCheckedAt: now.addingTimeInterval(-3600), now: now))
        #expect(ServerTrashCheckPolicy.isDue(lastCheckedAt: now.addingTimeInterval(-21 * 3600), now: now))
    }

    @Test("last check in the future (clock moved back) → due")
    func dueWhenClockMovedBack() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ServerTrashCheckPolicy.isDue(lastCheckedAt: now.addingTimeInterval(3600), now: now))
    }

    @Test("default reminder is Sunday 10:00")
    func defaultReminder() {
        let c = ServerTrashCheckPolicy.reminderComponents(
            weekday: ServerTrashCheckPolicy.defaultWeekday,
            minuteOfDay: ServerTrashCheckPolicy.defaultMinuteOfDay
        )
        #expect(c.weekday == 1 && c.hour == 10 && c.minute == 0)
    }

    @Test("out-of-range settings clamp")
    func clamps() {
        let c = ServerTrashCheckPolicy.reminderComponents(weekday: 9, minuteOfDay: 5000)
        #expect(c.weekday == 7 && c.hour == 23 && c.minute == 59)
        let d = ServerTrashCheckPolicy.reminderComponents(weekday: 0, minuteOfDay: -5)
        #expect(d.weekday == 1 && d.hour == 0 && d.minute == 0)
    }

    @Test("next reminder: Wednesday → following Sunday 10:00; Sunday 10:30 → next week")
    func nextReminder() throws {
        // 2026-10-14 is a Wednesday.
        let wed = try #require(utc.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12)))
        let next = try #require(ServerTrashCheckPolicy.nextReminder(after: wed, weekday: 1, minuteOfDay: 600, calendar: utc))
        #expect(utc.dateComponents([.year, .month, .day, .hour, .minute], from: next) == DateComponents(year: 2026, month: 10, day: 18, hour: 10, minute: 0))

        let sunLate = try #require(utc.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 10, minute: 30)))
        let after = try #require(ServerTrashCheckPolicy.nextReminder(after: sunLate, weekday: 1, minuteOfDay: 600, calendar: utc))
        #expect(utc.component(.day, from: after) == 25)
    }

    @Test("reminder body singular and plural")
    func body() {
        #expect(ServerTrashCheckPolicy.reminderBody(count: 1).hasPrefix("1 photo trashed"))
        #expect(ServerTrashCheckPolicy.reminderBody(count: 3).hasPrefix("3 photos trashed"))
    }
}
