import Foundation
import Testing
@testable import CairnCore
@testable import CairnIOSCore

/// Fork: reverse deletes. Phone-delete runs merged into the Runs tab.
@Suite("PhoneDeleteRuns")
struct PhoneDeleteRunsTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func cairnRun(_ id: String, at seconds: TimeInterval) -> CairnFixtures.RunFixture {
        .init(id: id, startedAt: t0.addingTimeInterval(seconds), durationMs: 0, trashed: 1,
              restored: 0, dryRun: false, status: .complete, tag: "cairn/v1/run/\(id)", notes: "")
    }

    private func phoneRun(_ id: String, at seconds: TimeInterval, outcome: PhoneDeleteRun.Outcome = .deleted) -> PhoneDeleteRun {
        let target = LocalDeleteJournalEntry.Target(
            localIdentifier: "L1", checksums: ["ck1"], serverAssetId: "srv1", originalFileName: "IMG_1.MOV"
        )
        return PhoneDeleteRun(runId: id, startedAt: t0.addingTimeInterval(seconds), durationMs: 5,
                              targets: [target], deletedCount: 1, outcome: outcome)
    }

    @Test("merge interleaves by date and fills run assets")
    func mergeOrderAndAssets() {
        let merged = PhoneDeleteRuns.merge(
            [phoneRun("phone-x", at: 50)],
            into: [cairnRun("r-new", at: 100), cairnRun("r-old", at: 0)],
            assets: ["r-new": []]
        )
        #expect(merged.runs.map(\.id) == ["r-new", "phone-x", "r-old"])
        let asset = merged.assets["phone-x"]?.first
        #expect(asset?.assetId == "srv1")
        #expect(asset?.checksum == "ck1")
        #expect(asset?.kind == .video)
        #expect(merged.assets["r-new"] != nil)
    }

    @Test("merge is idempotent: old phone runs are replaced, not duplicated")
    func mergeReplaces() {
        let once = PhoneDeleteRuns.merge([phoneRun("phone-x", at: 50)], into: [cairnRun("r", at: 0)], assets: [:])
        let twice = PhoneDeleteRuns.merge([phoneRun("phone-y", at: 60)], into: once.runs, assets: once.assets)
        #expect(twice.runs.map(\.id) == ["phone-y", "r"])
        #expect(twice.assets["phone-x"] == nil)
    }

    @Test("deleted run → complete with count; failed run → aborted with nothing deleted")
    func fixtureMapping() {
        let ok = CairnFixtures.RunFixture.from(phoneRun("phone-a", at: 0))
        #expect(ok.isPhoneDelete)
        #expect(ok.status == .complete)
        #expect(ok.trashed == 1)
        #expect(ok.tag == nil)

        let failed = CairnFixtures.RunFixture.from(phoneRun("phone-b", at: 0, outcome: .failed(message: "Declined")))
        #expect(failed.status == .aborted)
        #expect(failed.trashed == 0)
        #expect(failed.phoneDeleteHeaderTitle == "Nothing deleted on iPhone")
    }
}
