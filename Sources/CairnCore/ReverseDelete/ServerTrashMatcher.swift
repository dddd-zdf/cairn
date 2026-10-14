import Foundation

/// One phone asset proposed for deletion because its Immich copy is in
/// Immich's trash. `serverAsset` is the trashed primary (photo, video, or
/// Live Photo still) that matched; `checksums` is the phone asset's full
/// cached set (two entries for a Live Photo).
public struct LocalDeleteCandidate: Sendable, Equatable, Identifiable {
    public let localIdentifier: String
    public let checksums: Set<Checksum>
    public let serverAsset: ServerAsset

    public var id: String { localIdentifier }

    public init(localIdentifier: String, checksums: Set<Checksum>, serverAsset: ServerAsset) {
        self.localIdentifier = localIdentifier
        self.checksums = checksums
        self.serverAsset = serverAsset
    }
}

/// Inputs to `ServerTrashMatcher.match`. Every set is precomputed by the
/// host so the matcher stays a pure function.
public struct ServerTrashMatchInput: Sendable {
    /// Trashed primaries from Immich: visibility timeline or archive.
    /// Live Photo motion videos (visibility hidden) are deliberately not
    /// needed — Immich trashes only the still when a Live Photo is
    /// deleted on the web, so the still is the signal. Non-trashed rows
    /// are ignored.
    public let trashedServerAssets: [ServerAsset]
    /// `localIdentifier → current checksums`, restricted to assets that
    /// are alive in the phone library and deletable by the user.
    public let liveLocalHashes: [String: Set<Checksum>]
    /// `EditRetirementStore` snapshot: first checksums cairn saw per id.
    public let firstObserved: [String: Set<Checksum>]
    /// Ids whose cached checksums were imputed from the server rather
    /// than hashed on the phone.
    public let imputedIdentifiers: Set<String>
    /// Checksums cairn has observed for this account, already narrowed to
    /// the indexing scope.
    public let inPurview: Set<Checksum>
    /// User's keep list.
    public let excluded: Set<Checksum>
    /// Checksums cairn itself moved to Immich trash.
    public let trashedByCairn: Set<Checksum>

    public init(
        trashedServerAssets: [ServerAsset],
        liveLocalHashes: [String: Set<Checksum>],
        firstObserved: [String: Set<Checksum>] = [:],
        imputedIdentifiers: Set<String> = [],
        inPurview: Set<Checksum>,
        excluded: Set<Checksum> = [],
        trashedByCairn: Set<Checksum> = []
    ) {
        self.trashedServerAssets = trashedServerAssets
        self.liveLocalHashes = liveLocalHashes
        self.firstObserved = firstObserved
        self.imputedIdentifiers = imputedIdentifiers
        self.inPurview = inPurview
        self.excluded = excluded
        self.trashedByCairn = trashedByCairn
    }
}

/// Why a phone asset whose bytes match an Immich-trashed asset was not
/// proposed. Counted so the review sheet can say what it left alone.
public enum ServerTrashSkipReason: String, Sendable, CaseIterable, Codable {
    /// cairn trashed it on Immich after a phone delete, and the photo is
    /// back on the phone (recovered from Recently Deleted). Deleting it
    /// again would undo the user's recovery.
    case trashedByCairn
    /// On the keep list.
    case excluded
    /// cairn never observed it for this account, or it's outside the
    /// indexing scope.
    case outOfPurview
    /// Checksums were imputed from the server, not hashed on the phone.
    case notVerified
    /// Edited on the phone since cairn first saw it, and the original
    /// version is not in Immich's trash. Only the edit was deleted on
    /// Immich; the phone holds both versions, so leave it.
    case editedOriginalKept
}

public struct ServerTrashMatch: Sendable, Equatable {
    /// Newest `fileCreatedAt` first.
    public let candidates: [LocalDeleteCandidate]
    public let skipped: [ServerTrashSkipReason: Int]

    public init(candidates: [LocalDeleteCandidate], skipped: [ServerTrashSkipReason: Int]) {
        self.candidates = candidates
        self.skipped = skipped
    }

    public var skippedTotal: Int { skipped.values.reduce(0, +) }
}

/// Matches assets trashed on Immich to live phone assets by SHA1. The
/// reverse of the main pipeline: Immich trash → phone Recently Deleted.
///
/// A live phone asset is a candidate when one of its **current**
/// checksums equals the checksum of a trashed Immich primary, and none of
/// the skip rules apply. Rules, in order:
///
/// 1. Any of its checksums was trashed by cairn → `trashedByCairn`.
/// 2. Any current or first-observed checksum is excluded → `excluded`.
/// 3. The matched checksum isn't in purview → `outOfPurview`.
/// 4. Its cache entry is imputed → `notVerified`.
/// 5. Edited since first observed (first-observed set minus current set
///    is non-empty) and none of those retired checksums is in the trashed
///    set → `editedOriginalKept`.
///
/// Live Photos: matching on the still is enough. The motion video
/// checksum is neither required nor consulted.
///
/// Edits, in terms of ARCHITECTURE.md "Edit semantics": Immich holds
/// `SHA1_O` and `SHA1_E`, the phone's cache holds `SHA1_E`. Trashing
/// `SHA1_O` alone on the web (cleaning up the old version) never matches,
/// because the current bytes are `SHA1_E`. Trashing `SHA1_E` alone hits
/// rule 5 and is skipped. Trashing both matches. An edit that never
/// reached Immich can't match either; the user deletes it by hand.
public enum ServerTrashMatcher {

    public static func match(_ input: ServerTrashMatchInput) -> ServerTrashMatch {
        var trashedByChecksum: [Checksum: ServerAsset] = [:]
        for asset in input.trashedServerAssets where asset.isTrashed {
            // Immich enforces one asset per checksum per user; keep the
            // first if a server ever returns duplicates.
            if trashedByChecksum[asset.checksum] == nil {
                trashedByChecksum[asset.checksum] = asset
            }
        }
        guard !trashedByChecksum.isEmpty else {
            return ServerTrashMatch(candidates: [], skipped: [:])
        }
        let trashedChecksums = Set(trashedByChecksum.keys)

        var candidates: [LocalDeleteCandidate] = []
        var skipped: [ServerTrashSkipReason: Int] = [:]

        // Sorted for deterministic output when two ids tie on date.
        for localId in input.liveLocalHashes.keys.sorted() {
            guard let current = input.liveLocalHashes[localId] else { continue }
            let hits = current.intersection(trashedChecksums)
            guard let matchedChecksum = hits.sorted(by: { $0.base64 < $1.base64 }).first,
                  let serverAsset = trashedByChecksum[matchedChecksum]
            else { continue }

            let first = input.firstObserved[localId] ?? []
            let reason: ServerTrashSkipReason? = {
                if !current.isDisjoint(with: input.trashedByCairn) { return .trashedByCairn }
                if !current.union(first).isDisjoint(with: input.excluded) { return .excluded }
                if !input.inPurview.contains(matchedChecksum) { return .outOfPurview }
                if input.imputedIdentifiers.contains(localId) { return .notVerified }
                let retired = first.subtracting(current)
                if !retired.isEmpty, retired.isDisjoint(with: trashedChecksums) { return .editedOriginalKept }
                return nil
            }()

            if let reason {
                skipped[reason, default: 0] += 1
            } else {
                candidates.append(LocalDeleteCandidate(
                    localIdentifier: localId,
                    checksums: current,
                    serverAsset: serverAsset
                ))
            }
        }

        candidates.sort {
            ($0.serverAsset.fileCreatedAt ?? .distantPast) > ($1.serverAsset.fileCreatedAt ?? .distantPast)
        }
        return ServerTrashMatch(candidates: candidates, skipped: skipped)
    }

    // MARK: - Safety

    /// Limits for one phone-delete batch. Looser than the Immich-side
    /// percent rail because a deliberate web cleanup can be large, and
    /// iOS keeps everything in Recently Deleted for 30 days anyway.
    public struct Limits: Sendable, Equatable {
        /// Fraction of the live phone library one batch may delete.
        public let maxFraction: Double
        /// Batches at or below this size skip the fraction check.
        public let floor: Int

        public init(maxFraction: Double = 0.10, floor: Int = 25) {
            self.maxFraction = maxFraction
            self.floor = floor
        }

        public static let `default` = Limits()
    }

    public enum SafetyDecision: Sendable, Equatable {
        case proceed
        case abort(reason: String)
    }

    /// Run before showing the delete button and again right before the
    /// PhotoKit call.
    public static func evaluate(
        candidateCount: Int,
        liveLibraryCount: Int,
        limits: Limits = .default
    ) -> SafetyDecision {
        guard candidateCount > 0 else { return .proceed }
        guard liveLibraryCount > 0 else {
            return .abort(reason: "Photo library looks empty. Check Photos access and try again.")
        }
        guard candidateCount > limits.floor else { return .proceed }
        let fraction = Double(candidateCount) / Double(liveLibraryCount)
        if fraction > limits.maxFraction {
            let pct = String(format: "%.1f", fraction * 100)
            let limit = String(format: "%.0f", limits.maxFraction * 100)
            return .abort(reason: "\(candidateCount) photos is \(pct)% of this iPhone's library; the limit is \(limit)%. Pick a shorter time range.")
        }
        return .proceed
    }
}

/// Deletes phone assets by platform identifier. iOS:
/// `PHAssetChangeRequest.deleteAssets` in one `performChanges` batch, so
/// the system shows a single confirmation and items go to Recently
/// Deleted.
public protocol LocalAssetDeleter: Sendable {
    /// Returns the identifiers actually deleted. Ids that no longer
    /// exist or can't be deleted are dropped before the request. Throws
    /// `LocalDeleteError.userCancelled` when the user declines the
    /// system prompt.
    func deleteAssets(localIdentifiers: [String]) async throws -> [String]
}

public enum LocalDeleteError: Error, Equatable, CustomStringConvertible {
    case userCancelled
    case failed(String)

    public var description: String {
        switch self {
        case .userCancelled: return "Cancelled at the system prompt"
        case .failed(let message): return message
        }
    }
}
