import Foundation
import Observation
import CairnCore

/// Owns everything the reverse direction (Immich trash → phone) needs at
/// runtime: its settings, the review sheet state, the pending count, and
/// the weekly reminder. Kept out of `CairnAppModel` / `CairnSettings` so
/// the feature touches cairn's own files only through a few one-line
/// hooks (see `docs/reverse-deletes.md`).
///
/// The app target supplies `host` (Immich + PhotoKit access) at bootstrap
/// and calls `syncDidFinish()` after every successful sync.
@Observable
@MainActor
public final class ReverseDeleteController {

    public static let shared = ReverseDeleteController()

    public enum ReviewState: Sendable, Equatable {
        case idle
        case scanning
        case loaded(ServerTrashReview)
        case deleting(ServerTrashReview)
        case error(String)
    }

    /// App-side capabilities. Closures so CairnIOSCore never depends on
    /// the app target.
    public struct Host: Sendable {
        public var isReady: @Sendable () async -> Bool
        public var find: @Sendable (_ lookbackDays: Int) async throws -> ServerTrashReview
        public var delete: @Sendable (_ candidates: [LocalDeleteCandidate]) async throws -> [String]
        public var keep: @Sendable (_ candidates: [LocalDeleteCandidate]) async -> Void

        public init(
            isReady: @escaping @Sendable () async -> Bool,
            find: @escaping @Sendable (Int) async throws -> ServerTrashReview,
            delete: @escaping @Sendable ([LocalDeleteCandidate]) async throws -> [String],
            keep: @escaping @Sendable ([LocalDeleteCandidate]) async -> Void
        ) {
            self.isReady = isReady
            self.find = find
            self.delete = delete
            self.keep = keep
        }
    }

    // MARK: - Settings (UserDefaults, own namespace)

    /// Off by default. Turning it on asks for notification permission
    /// once and makes the next sync run a check.
    public var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            defaults.set(isEnabled, forKey: Keys.enabled)
            Task { await enabledDidChange() }
        }
    }

    public var reminderWeekday: Int {
        didSet {
            guard oldValue != reminderWeekday else { return }
            defaults.set(reminderWeekday, forKey: Keys.weekday)
            Task { await refreshReminder() }
        }
    }

    public var reminderMinuteOfDay: Int {
        didSet {
            guard oldValue != reminderMinuteOfDay else { return }
            defaults.set(reminderMinuteOfDay, forKey: Keys.minuteOfDay)
            Task { await refreshReminder() }
        }
    }

    // MARK: - State

    /// From the last 30-day check. Drives the Status line and reminder.
    public private(set) var pendingCount: Int
    public var reviewState: ReviewState = .idle
    public var isSheetPresented = false

    @ObservationIgnored public var host: Host?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var lastCheckedAt: Date?

    private enum Keys {
        static let enabled = "cairn.reverseDelete.enabled"
        static let weekday = "cairn.reverseDelete.reminderWeekday"
        static let minuteOfDay = "cairn.reverseDelete.reminderMinuteOfDay"
        static let pendingCount = "cairn.reverseDelete.pendingCount"
        static let lastCheckedAt = "cairn.reverseDelete.lastCheckedAt"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Keys.enabled)
        self.reminderWeekday = (defaults.object(forKey: Keys.weekday) as? Int) ?? ServerTrashCheckPolicy.defaultWeekday
        self.reminderMinuteOfDay = (defaults.object(forKey: Keys.minuteOfDay) as? Int) ?? ServerTrashCheckPolicy.defaultMinuteOfDay
        self.pendingCount = defaults.integer(forKey: Keys.pendingCount)
        self.lastCheckedAt = defaults.object(forKey: Keys.lastCheckedAt) as? Date
    }

    // MARK: - Review sheet

    /// Open the sheet and scan the full 30 days straight away. Used by the
    /// Settings row, the Status line, and the reminder notification.
    public func openReview() {
        isSheetPresented = true
        startScan(lookbackDays: ServerTrashCheckPolicy.lookbackDays)
    }

    public func startScan(lookbackDays: Int) {
        reviewState = .scanning
        Task {
            guard let host = await readyHost() else {
                reviewState = .error("cairn isn't connected to Immich yet. Try again in a moment.")
                return
            }
            do {
                let review = try await host.find(lookbackDays)
                reviewState = .loaded(review)
                await recordCheck(review)
            } catch {
                reviewState = .error(error.localizedDescription)
            }
        }
    }

    public func delete(_ candidates: [LocalDeleteCandidate]) {
        guard case .loaded(let review) = reviewState, let host else { return }
        reviewState = .deleting(review)
        Task {
            do {
                let deleted = try await host.delete(candidates)
                let remaining = review.removing(Set(deleted))
                reviewState = .loaded(remaining)
                await recordCheck(remaining)
            } catch LocalDeleteError.userCancelled {
                reviewState = .loaded(review)
            } catch {
                reviewState = .error(String(describing: error))
            }
        }
    }

    public func keep(_ candidates: [LocalDeleteCandidate]) {
        guard case .loaded(let review) = reviewState, let host else { return }
        Task {
            await host.keep(candidates)
            let remaining = review.removing(Set(candidates.map(\.localIdentifier)))
            reviewState = .loaded(remaining)
            await recordCheck(remaining)
        }
    }

    public func closeReview() {
        isSheetPresented = false
        reviewState = .idle
    }

    // MARK: - Background check

    /// Hook: call after every successful sync (foreground, background,
    /// Shortcut). Runs at most about once a day; never prompts.
    public func syncDidFinish() async {
        guard isEnabled, let host,
              ServerTrashCheckPolicy.isDue(lastCheckedAt: lastCheckedAt, now: Date()),
              await host.isReady(),
              let review = try? await host.find(ServerTrashCheckPolicy.lookbackDays)
        else { return }
        await recordCheck(review)
    }

    // MARK: - Private

    /// Only full-window results update the pending count; a shorter
    /// manual scan would undercount.
    private func recordCheck(_ review: ServerTrashReview) async {
        guard review.lookbackDays >= ServerTrashCheckPolicy.lookbackDays else { return }
        lastCheckedAt = Date()
        defaults.set(lastCheckedAt, forKey: Keys.lastCheckedAt)
        pendingCount = review.candidates.count
        defaults.set(pendingCount, forKey: Keys.pendingCount)
        await refreshReminder()
    }

    private func enabledDidChange() async {
        if isEnabled {
            #if canImport(UserNotifications)
            await ServerTrashReminderScheduler.requestAuthorization()
            #endif
            lastCheckedAt = nil
            defaults.removeObject(forKey: Keys.lastCheckedAt)
        } else {
            pendingCount = 0
            defaults.set(0, forKey: Keys.pendingCount)
        }
        await refreshReminder()
    }

    private func refreshReminder() async {
        #if canImport(UserNotifications)
        await ServerTrashReminderScheduler.update(
            pendingCount: isEnabled ? pendingCount : 0,
            weekday: reminderWeekday,
            minuteOfDay: reminderMinuteOfDay
        )
        #endif
    }

    /// Cold launch from the notification can land before bootstrap has
    /// built the Immich client; wait up to ~10 s.
    private func readyHost() async -> Host? {
        for _ in 0..<20 {
            if let host, await host.isReady() { return host }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return nil
    }
}
