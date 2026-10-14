import Foundation

/// One phone-delete run folded from `LocalDeleteJournal` rows, for the
/// Runs tab. Pure so the folding is testable; the iOS side maps it onto
/// cairn's `RunFixture`.
public struct PhoneDeleteRun: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        /// iOS accepted the delete; items are in Recently Deleted.
        case deleted
        /// Size limit refused the batch before PhotoKit was called.
        case aborted(reason: String)
        /// PhotoKit failed or the user declined the system prompt.
        case failed(message: String)
        /// `planned` with no outcome row: the app died mid-delete.
        case unfinished
    }

    public let runId: String
    public let startedAt: Date
    public let durationMs: Int
    public let targets: [LocalDeleteJournalEntry.Target]
    public let deletedCount: Int
    public let outcome: Outcome

    /// Same "<status> · <detail>" shape as `JournalReader` notes, so
    /// `RunDetailSheet`'s aborted-reason parsing works unchanged.
    public var notes: String {
        switch outcome {
        case .deleted:
            return "\(deletedCount) moved to iPhone Recently Deleted (trashed on Immich)"
        case .aborted(let reason):
            return "aborted · \(reason)"
        case .failed(let message):
            return "aborted · \(message)"
        case .unfinished:
            return "aborted · cairn closed before iOS confirmed the delete. Check Recently Deleted on the iPhone."
        }
    }

    /// Newest first, matching `JournalReader.summarize`.
    public static func summarize(_ entries: [LocalDeleteJournalEntry]) -> [PhoneDeleteRun] {
        var byRun: [String: [LocalDeleteJournalEntry]] = [:]
        for entry in entries {
            byRun[entry.runId, default: []].append(entry)
        }
        return byRun.values
            .map { fold($0.sorted { $0.timestamp < $1.timestamp }) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private static func fold(_ sorted: [LocalDeleteJournalEntry]) -> PhoneDeleteRun {
        var targets: [LocalDeleteJournalEntry.Target] = []
        var deletedIds: [String] = []
        var durationMs = 0
        var outcome: Outcome = .unfinished
        for entry in sorted {
            switch entry.event {
            case .planned(let t):
                targets = t
            case .succeeded(let ids, let ms):
                deletedIds = ids
                durationMs = ms ?? 0
                outcome = .deleted
            case .failed(_, let message):
                outcome = .failed(message: message)
            case .aborted(let reason):
                outcome = .aborted(reason: reason)
            }
        }
        // When iOS deleted fewer than planned (some vanished meanwhile),
        // list only the ones it actually deleted.
        if outcome == .deleted {
            let kept = Set(deletedIds)
            targets = targets.filter { kept.contains($0.localIdentifier) }
        }
        return PhoneDeleteRun(
            runId: sorted[0].runId,
            startedAt: sorted[0].timestamp,
            durationMs: durationMs,
            targets: targets,
            deletedCount: deletedIds.count,
            outcome: outcome
        )
    }
}
