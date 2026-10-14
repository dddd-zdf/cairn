import Foundation
import CairnCore

/// Puts phone-delete runs (Immich trash → iPhone) into cairn's Runs tab.
/// The rows come from `LocalDeleteJournal`, which stays a separate file;
/// they're only merged into the view model. Run ids start with "phone-"
/// (see `AppDependencies+ReverseDelete.swift`), which is how the Runs
/// screens tell them apart.
public enum PhoneDeleteRuns {

    /// Replace any phone-delete runs in `runs` / `runAssets` with
    /// `phoneRuns`. Idempotent, so it can follow every refresh.
    public static func merge(
        _ phoneRuns: [PhoneDeleteRun],
        into runs: [CairnFixtures.RunFixture],
        assets: [String: [CairnFixtures.CandidateFixture]]
    ) -> (runs: [CairnFixtures.RunFixture], assets: [String: [CairnFixtures.CandidateFixture]]) {
        var outRuns = runs.filter { !$0.isPhoneDelete }
        var outAssets = assets.filter { !CairnFixtures.RunFixture.isPhoneDeleteId($0.key) }
        for run in phoneRuns {
            outRuns.append(.from(run))
            outAssets[run.runId] = run.targets.map(CairnFixtures.CandidateFixture.from)
        }
        outRuns.sort { $0.startedAt > $1.startedAt }
        return (outRuns, outAssets)
    }
}

extension CairnFixtures.RunFixture {

    static func isPhoneDeleteId(_ id: String) -> Bool { id.hasPrefix("phone-") }

    /// True for runs that deleted photos from this iPhone, not from Immich.
    public var isPhoneDelete: Bool { Self.isPhoneDeleteId(id) }

    /// `trashed` carries the phone-delete count. Failed and unfinished
    /// runs show as aborted, with the message in `notes`.
    static func from(_ run: PhoneDeleteRun) -> CairnFixtures.RunFixture {
        let deleted = run.outcome == .deleted
        return CairnFixtures.RunFixture(
            id: run.runId,
            startedAt: run.startedAt,
            durationMs: run.durationMs,
            trashed: deleted ? run.deletedCount : 0,
            restored: 0,
            dryRun: false,
            status: deleted ? .complete : .aborted,
            tag: nil,
            notes: run.notes
        )
    }

    /// Run-detail header for phone-delete runs.
    var phoneDeleteHeaderTitle: String {
        if status == .aborted { return "Nothing deleted on iPhone" }
        let suffix = trashed == 1 ? "" : "s"
        return "\(trashed) photo\(suffix) moved to iPhone Recently Deleted"
    }
}

extension CairnFixtures.CandidateFixture {

    /// `assetId` is the trashed Immich asset, so thumbnails still load
    /// while Immich keeps it in its trash.
    static func from(_ target: LocalDeleteJournalEntry.Target) -> CairnFixtures.CandidateFixture {
        let name = target.originalFileName ?? "asset-\(target.serverAssetId.prefix(8))"
        let ext = (name as NSString).pathExtension.lowercased()
        let isVideo = ["mov", "mp4", "m4v", "avi", "3gp"].contains(ext)
        let date: String = target.fileCreatedAt.map {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: $0)
        } ?? "—"
        return CairnFixtures.CandidateFixture(
            name: name,
            kind: isVideo ? .video : .photo,
            date: date,
            bytes: 0,
            isLivePair: false,
            assetId: target.serverAssetId,
            checksum: target.checksums.first
        )
    }
}
