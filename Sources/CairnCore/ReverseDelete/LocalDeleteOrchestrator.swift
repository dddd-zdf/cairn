import Foundation

public struct LocalDeleteRunSummary: Sendable, Equatable {
    public let runId: String
    public let deletedLocalIdentifiers: [String]
    public let aborted: Bool
    public let abortReason: String?
}

/// Deletes phone assets whose Immich copies are in Immich's trash, and
/// journals the run to `LocalDeleteJournal`. Sequence:
///
/// 1. Re-run `ServerTrashMatcher.evaluate`. Over the limit → journal
///    `aborted` and return without touching the library.
/// 2. Journal `planned` (write-ahead).
/// 3. One `LocalAssetDeleter.deleteAssets` call. Journal
///    `succeeded` or `failed` (including the user
///    declining the system prompt), then rethrow failures.
///
/// The caller is responsible for the user having reviewed `candidates`.
public struct LocalDeleteOrchestrator: Sendable {
    public let deleter: LocalAssetDeleter
    public let journal: LocalDeleteJournal
    public let now: @Sendable () -> Date

    public init(
        deleter: LocalAssetDeleter,
        journal: LocalDeleteJournal,
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
            try await journal.append(LocalDeleteJournalEntry(timestamp: now(), runId: runId, event: .aborted(reason: reason)))
            return LocalDeleteRunSummary(runId: runId, deletedLocalIdentifiers: [], aborted: true, abortReason: reason)
        }

        let targets = candidates.map {
            LocalDeleteJournalEntry.Target(
                localIdentifier: $0.localIdentifier,
                checksums: $0.checksums.map(\.base64).sorted(),
                serverAssetId: $0.serverAsset.id,
                originalFileName: $0.serverAsset.originalFileName,
                fileCreatedAt: $0.serverAsset.fileCreatedAt
            )
        }
        try await journal.append(LocalDeleteJournalEntry(timestamp: now(), runId: runId, event: .planned(targets: targets)))

        let ids = candidates.map(\.localIdentifier)
        let started = now()
        do {
            let deleted = try await deleter.deleteAssets(localIdentifiers: ids)
            let ms = Int((now().timeIntervalSince(started) * 1000).rounded())
            try await journal.append(LocalDeleteJournalEntry(
                timestamp: now(),
                runId: runId,
                event: .succeeded(localIdentifiers: deleted, durationMs: ms)
            ))
            return LocalDeleteRunSummary(runId: runId, deletedLocalIdentifiers: deleted, aborted: false, abortReason: nil)
        } catch {
            let message = (error as? LocalDeleteError)?.description ?? String(describing: error)
            try? await journal.append(LocalDeleteJournalEntry(
                timestamp: now(),
                runId: runId,
                event: .failed(localIdentifiers: ids, message: message)
            ))
            throw error
        }
    }
}
