import Foundation

/// Result of one reverse-direction scan, ready for the review sheet.
/// `liveLibraryCount` feeds `ServerTrashMatcher.evaluate`, which the sheet
/// re-runs as the user skips rows.
public struct ServerTrashReview: Sendable, Equatable {
    public let candidates: [LocalDeleteCandidate]
    public let skipped: [ServerTrashSkipReason: Int]
    public let trashedOnServer: Int
    public let lookbackDays: Int
    public let liveLibraryCount: Int

    public init(
        candidates: [LocalDeleteCandidate],
        skipped: [ServerTrashSkipReason: Int] = [:],
        trashedOnServer: Int = 0,
        lookbackDays: Int = ServerTrashCheckPolicy.lookbackDays,
        liveLibraryCount: Int = 0
    ) {
        self.candidates = candidates
        self.skipped = skipped
        self.trashedOnServer = trashedOnServer
        self.lookbackDays = lookbackDays
        self.liveLibraryCount = liveLibraryCount
    }

    public static let empty = ServerTrashReview(candidates: [])

    /// Non-nil when a batch of `count` would be refused.
    public func blockedReason(forCount count: Int) -> String? {
        if case .abort(let reason) = ServerTrashMatcher.evaluate(candidateCount: count, liveLibraryCount: liveLibraryCount) {
            return reason
        }
        return nil
    }

    public func removing(_ localIdentifiers: Set<String>) -> ServerTrashReview {
        ServerTrashReview(
            candidates: candidates.filter { !localIdentifiers.contains($0.localIdentifier) },
            skipped: skipped,
            trashedOnServer: trashedOnServer,
            lookbackDays: lookbackDays,
            liveLibraryCount: liveLibraryCount
        )
    }
}
