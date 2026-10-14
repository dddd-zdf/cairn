import Foundation
import Testing
@testable import CairnCore

@Suite("ServerTrashMatcher")
struct ServerTrashMatcherTests {

    private func ck(_ s: String) -> Checksum { Checksum(base64: s) }

    private func trashed(_ id: String, _ checksum: String, live: String? = nil, created: Date? = nil) -> ServerAsset {
        ServerAsset(id: id, checksum: ck(checksum), livePhotoVideoId: live, isTrashed: true, fileCreatedAt: created)
    }

    private func input(
        trashed: [ServerAsset],
        local: [String: Set<Checksum>],
        firstObserved: [String: Set<Checksum>] = [:],
        imputed: Set<String> = [],
        inPurview: Set<Checksum>? = nil,
        excluded: Set<Checksum> = [],
        trashedByCairn: Set<Checksum> = []
    ) -> ServerTrashMatchInput {
        ServerTrashMatchInput(
            trashedServerAssets: trashed,
            liveLocalHashes: local,
            firstObserved: firstObserved,
            imputedIdentifiers: imputed,
            inPurview: inPurview ?? Set(local.values.flatMap { $0 }),
            excluded: excluded,
            trashedByCairn: trashedByCairn
        )
    }

    @Test("plain photo trashed on Immich is a candidate")
    func plainMatch() {
        let r = ServerTrashMatcher.match(input(
            trashed: [trashed("s1", "A")],
            local: ["L1": [ck("A")], "L2": [ck("B")]]
        ))
        #expect(r.candidates.map(\.localIdentifier) == ["L1"])
        #expect(r.candidates.first?.serverAsset.id == "s1")
        #expect(r.skipped.isEmpty)
    }

    @Test("non-trashed server rows never match")
    func ignoresNonTrashed() {
        let alive = ServerAsset(id: "s1", checksum: ck("A"), isTrashed: false)
        let r = ServerTrashMatcher.match(input(trashed: [alive], local: ["L1": [ck("A")]]))
        #expect(r.candidates.isEmpty)
    }

    @Test("Live Photo matches on the still alone; motion checksum not required")
    func livePhotoStillIsEnough() {
        let r = ServerTrashMatcher.match(input(
            trashed: [trashed("still", "S", live: "motion-id")],
            local: ["L1": [ck("S"), ck("M")]]
        ))
        #expect(r.candidates.count == 1)
        #expect(r.candidates[0].checksums == [ck("S"), ck("M")])
    }

    @Test("asset cairn trashed and the user recovered on the phone is skipped")
    func skipsCairnTrashed() {
        let r = ServerTrashMatcher.match(input(
            trashed: [trashed("s1", "A")],
            local: ["L1": [ck("A")]],
            trashedByCairn: [ck("A")]
        ))
        #expect(r.candidates.isEmpty)
        #expect(r.skipped[.trashedByCairn] == 1)
    }

    @Test("excluded checksum (current or first-observed) is skipped")
    func skipsExcluded() {
        let r = ServerTrashMatcher.match(input(
            trashed: [trashed("s1", "A"), trashed("s2", "E")],
            local: ["L1": [ck("A")], "L2": [ck("E")]],
            firstObserved: ["L2": [ck("O")]],
            excluded: [ck("A"), ck("O")]
        ))
        #expect(r.candidates.isEmpty)
        #expect(r.skipped[.excluded] == 2)
    }

    @Test("checksum outside this account's observed set is skipped")
    func skipsOutOfPurview() {
        let r = ServerTrashMatcher.match(input(
            trashed: [trashed("s1", "A")],
            local: ["L1": [ck("A")]],
            inPurview: []
        ))
        #expect(r.candidates.isEmpty)
        #expect(r.skipped[.outOfPurview] == 1)
    }

    @Test("imputed cache entry is skipped until verified")
    func skipsImputed() {
        let r = ServerTrashMatcher.match(input(
            trashed: [trashed("s1", "A")],
            local: ["L1": [ck("A")]],
            imputed: ["L1"]
        ))
        #expect(r.candidates.isEmpty)
        #expect(r.skipped[.notVerified] == 1)
    }

    @Test("edited photo: only the edit trashed on Immich → skipped, original kept")
    func editOnlyEditTrashed() {
        let r = ServerTrashMatcher.match(input(
            trashed: [trashed("sE", "E")],
            local: ["L1": [ck("E")]],
            firstObserved: ["L1": [ck("O")]]
        ))
        #expect(r.candidates.isEmpty)
        #expect(r.skipped[.editedOriginalKept] == 1)
    }

    @Test("edited photo: original and edit both trashed → candidate")
    func editBothTrashed() {
        let r = ServerTrashMatcher.match(input(
            trashed: [trashed("sE", "E"), trashed("sO", "O")],
            local: ["L1": [ck("E")]],
            firstObserved: ["L1": [ck("O")]]
        ))
        #expect(r.candidates.map(\.localIdentifier) == ["L1"])
        #expect(r.candidates[0].serverAsset.id == "sE")
    }

    @Test("edited photo: only the original trashed (web cleanup) → no match at all")
    func editOnlyOriginalTrashed() {
        let r = ServerTrashMatcher.match(input(
            trashed: [trashed("sO", "O")],
            local: ["L1": [ck("E")]],
            firstObserved: ["L1": [ck("O")]]
        ))
        #expect(r.candidates.isEmpty)
        #expect(r.skipped.isEmpty)
    }

    @Test("unedited photo: first-observed equal to current doesn't trigger the edit rule")
    func uneditedFirstObserved() {
        let r = ServerTrashMatcher.match(input(
            trashed: [trashed("s1", "A")],
            local: ["L1": [ck("A")]],
            firstObserved: ["L1": [ck("A")]]
        ))
        #expect(r.candidates.count == 1)
    }

    @Test("edited Live Photo: still original trashed is enough even if motion retired too")
    func editedLivePhoto() {
        let r = ServerTrashMatcher.match(input(
            trashed: [trashed("sE", "SE", live: "m2"), trashed("sO", "SO", live: "m1")],
            local: ["L1": [ck("SE"), ck("ME")]],
            firstObserved: ["L1": [ck("SO"), ck("MO")]]
        ))
        #expect(r.candidates.count == 1)
    }

    @Test("candidates sort newest fileCreatedAt first")
    func sortsNewestFirst() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let r = ServerTrashMatcher.match(input(
            trashed: [trashed("s1", "A", created: old), trashed("s2", "B", created: new)],
            local: ["L1": [ck("A")], "L2": [ck("B")]]
        ))
        #expect(r.candidates.map(\.localIdentifier) == ["L2", "L1"])
    }

    // MARK: - Safety

    @Test("empty library aborts")
    func safetyEmptyLibrary() {
        if case .proceed = ServerTrashMatcher.evaluate(candidateCount: 1, liveLibraryCount: 0) {
            Issue.record("expected abort")
        }
    }

    @Test("at or below the floor always proceeds")
    func safetyFloor() {
        #expect(ServerTrashMatcher.evaluate(candidateCount: 25, liveLibraryCount: 30) == .proceed)
    }

    @Test("above the floor and above 10% aborts; at 10% proceeds")
    func safetyFraction() {
        #expect(ServerTrashMatcher.evaluate(candidateCount: 100, liveLibraryCount: 1000) == .proceed)
        if case .proceed = ServerTrashMatcher.evaluate(candidateCount: 101, liveLibraryCount: 1000) {
            Issue.record("expected abort")
        }
    }

    @Test("zero candidates proceed")
    func safetyZero() {
        #expect(ServerTrashMatcher.evaluate(candidateCount: 0, liveLibraryCount: 0) == .proceed)
    }
}

// MARK: - Orchestrator

actor FakeDeleter: LocalAssetDeleter {
    var calls: [[String]] = []
    var failWith: Error? = nil
    var drop: Set<String> = []

    func setFail(_ error: Error?) { failWith = error }
    func setDrop(_ ids: Set<String>) { drop = ids }

    func deleteAssets(localIdentifiers: [String]) async throws -> [String] {
        calls.append(localIdentifiers)
        if let failWith { throw failWith }
        return localIdentifiers.filter { !drop.contains($0) }
    }
}

@Suite("LocalDeleteOrchestrator")
struct LocalDeleteOrchestratorTests {

    private func tempJournal() -> LocalDeleteJournal {
        LocalDeleteJournal(path: URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "localdel-\(UUID().uuidString).jsonl"))
    }

    private func candidate(_ id: String) -> LocalDeleteCandidate {
        LocalDeleteCandidate(
            localIdentifier: id,
            checksums: [Checksum(base64: "ck-\(id)")],
            serverAsset: ServerAsset(id: "srv-\(id)", checksum: Checksum(base64: "ck-\(id)"), isTrashed: true, originalFileName: "IMG_\(id).HEIC")
        )
    }

    @Test("happy path: one delete call, planned then succeeded in the journal")
    func happyPath() async throws {
        let deleter = FakeDeleter()
        let journal = tempJournal()
        let orch = LocalDeleteOrchestrator(deleter: deleter, journal: journal)
        let summary = try await orch.run(runId: "r1", candidates: [candidate("1"), candidate("2")], liveLibraryCount: 1000)
        #expect(summary.deletedLocalIdentifiers == ["1", "2"])
        #expect(await deleter.calls == [["1", "2"]])
        let entries = try await journal.readAll()
        #expect(entries.count == 2)
        guard case .planned(let targets) = entries[0].event else { Issue.record("expected planned"); return }
        #expect(targets.map(\.serverAssetId) == ["srv-1", "srv-2"])
        #expect(targets[0].originalFileName == "IMG_1.HEIC")
        guard case .succeeded(let ids, _) = entries[1].event else { Issue.record("expected succeeded"); return }
        #expect(ids == ["1", "2"])
    }

    @Test("over the limit: aborted without calling the deleter")
    func overLimit() async throws {
        let deleter = FakeDeleter()
        let journal = tempJournal()
        let orch = LocalDeleteOrchestrator(deleter: deleter, journal: journal)
        let many = (0..<30).map { candidate("\($0)") }
        let summary = try await orch.run(runId: "r2", candidates: many, liveLibraryCount: 100)
        #expect(summary.aborted)
        #expect(await deleter.calls.isEmpty)
        let entries = try await journal.readAll()
        #expect(entries.count == 1)
        guard case .aborted = entries[0].event else { Issue.record("expected aborted"); return }
    }

    @Test("user cancel at the system prompt is journaled and rethrown")
    func userCancel() async throws {
        let deleter = FakeDeleter()
        await deleter.setFail(LocalDeleteError.userCancelled)
        let journal = tempJournal()
        let orch = LocalDeleteOrchestrator(deleter: deleter, journal: journal)
        await #expect(throws: LocalDeleteError.userCancelled) {
            _ = try await orch.run(runId: "r3", candidates: [candidate("1")], liveLibraryCount: 10)
        }
        let entries = try await journal.readAll()
        guard case .failed(_, let message) = entries.last?.event else { Issue.record("expected failed"); return }
        #expect(message.contains("Cancelled"))
    }

    @Test("ids the deleter drops are not reported as deleted")
    func partial() async throws {
        let deleter = FakeDeleter()
        await deleter.setDrop(["2"])
        let orch = LocalDeleteOrchestrator(deleter: deleter, journal: tempJournal())
        let summary = try await orch.run(runId: "r4", candidates: [candidate("1"), candidate("2")], liveLibraryCount: 1000)
        #expect(summary.deletedLocalIdentifiers == ["1"])
    }

    @Test("empty candidates: no journal, no deleter call")
    func empty() async throws {
        let deleter = FakeDeleter()
        let journal = tempJournal()
        let orch = LocalDeleteOrchestrator(deleter: deleter, journal: journal)
        _ = try await orch.run(runId: "r5", candidates: [], liveLibraryCount: 10)
        #expect(await deleter.calls.isEmpty)
        #expect(try await journal.readAll().isEmpty)
    }

    @Test("journal round-trips through its own file")
    func journalRoundTrip() async throws {
        let journal = tempJournal()
        let orch = LocalDeleteOrchestrator(deleter: FakeDeleter(), journal: journal)
        _ = try await orch.run(runId: "r6", candidates: [candidate("1")], liveLibraryCount: 1000)
        let reread = LocalDeleteJournal(path: journal.path)
        let entries = try await reread.readAll()
        #expect(entries.map(\.runId) == ["r6", "r6"])
    }
}
