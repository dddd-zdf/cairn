import Foundation

public struct LocalDeleteRunSummary: Sendable, Equatable {
    public let runId: String
    public let deletedLocalIdentifiers: [String]
    public let aborted: Bool
    public let abortReason: String?
}

/// Deletes phone assets whose Immich copies are in Immich's trash, and
/// journals the run. Sequence:
///
/// 1. Re-run `ServerTrashMatcher.evaluate`. Over the limit → journal
///    `localDeleteAborted` and return without touching the library.
/// 2. Journal `localDeletePlanned` (write-ahead).
/// 3. One `LocalAssetDeleter.deleteAssets` call. Journal
///    `localDeleteSucceeded` or `localDeleteFailed` (including the user
///    declining the system prompt), then rethrow failures.
///
/// The caller is responsible for the user having reviewed `candidates`.
public struct LocalDeleteOrchestrator: Sendable {
    public let deleter: LocalAssetDeleter
    public let journal: DeletionJournal
    public let now: @Sendable () -> Date

    public init(
        deleter: LocalAssetDeleter,
        journal: DeletionJournal,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.deleter = deleter
        self.journal = journal
        self.now = now
    }

    public func run(
        runId: String,
        candidates: [LocalDeleteCandidate],
        liveLibraryCount: Int,
        limits: ServerTrashMatcher.Limits = .default
    ) async throws -> LocalDeleteRunSummary {
        guard !candidates.isEmpty else {
            return LocalDeleteRunSummary(runId: runId, deletedLocalIdentifiers: [], aborted: false, abortReason: nil)
        }

        if case .abort(let reason) = ServerTrashMatcher.evaluate(
            candidateCount: candidates.count,
            liveLibraryCount: liveLibraryCount,
            limits: limits
        ) {
            try await journal.append(JournalEntry(timestamp: now(), runId: runId, event: .localDeleteAborted(reason: reason)))
            return LocalDeleteRunSummary(runId: runId, deletedLocalIdentifiers: [], aborted: true, abortReason: reason)
        }

        let targets = candidates.map {
            JournalEntry.LocalDeleteTarget(
                localIdentifier: $0.localIdentifier,
                checksums: $0.checksums.map(\.base64).sorted(),
                serverAssetId: $0.serverAsset.id,
                originalFileName: $0.serverAsset.originalFileName,
                fileCreatedAt: $0.serverAsset.fileCreatedAt
            )
        }
        try await journal.append(JournalEntry(timestamp: now(), runId: runId, event: .localDeletePlanned(targets: targets)))

        let ids = candidates.map(\.localIdentifier)
        let started = now()
        do {
            let deleted = try await deleter.deleteAssets(localIdentifiers: ids)
            let ms = Int((now().timeIntervalSince(started) * 1000).rounded())
            try await journal.append(JournalEntry(
                timestamp: now(),
                runId: runId,
                event: .localDeleteSucceeded(localIdentifiers: deleted, durationMs: ms)
            ))
            return LocalDeleteRunSummary(runId: runId, deletedLocalIdentifiers: deleted, aborted: false, abortReason: nil)
        } catch {
            let message = (error as? LocalDeleteError)?.description ?? String(describing: error)
            try? await journal.append(JournalEntry(
                timestamp: now(),
                runId: runId,
                event: .localDeleteFailed(localIdentifiers: ids, message: message)
            ))
            throw error
        }
    }
}
