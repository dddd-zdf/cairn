import Foundation
import Testing
@testable import CairnCore

@Suite("PhoneDeleteRun")
struct PhoneDeleteRunTests {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func target(_ id: String) -> LocalDeleteJournalEntry.Target {
        .init(localIdentifier: id, checksums: ["ck-\(id)"], serverAssetId: "srv-\(id)", originalFileName: "\(id).HEIC")
    }

    private func entry(_ runId: String, _ seconds: TimeInterval, _ event: LocalDeleteJournalEntry.Event) -> LocalDeleteJournalEntry {
        .init(timestamp: t0.addingTimeInterval(seconds), runId: runId, event: event)
    }

    @Test("empty journal → no runs")
    func empty() {
        #expect(PhoneDeleteRun.summarize([]).isEmpty)
    }

    @Test("planned + succeeded → deleted run with targets and duration")
    func succeeded() {
        let runs = PhoneDeleteRun.summarize([
            entry("phone-a", 0, .planned(targets: [target("1"), target("2")])),
            entry("phone-a", 2, .succeeded(localIdentifiers: ["1", "2"], durationMs: 1500)),
        ])
        #expect(runs.count == 1)
        let run = runs[0]
        #expect(run.runId == "phone-a")
        #expect(run.startedAt == t0)
        #expect(run.outcome == .deleted)
        #expect(run.deletedCount == 2)
        #expect(run.durationMs == 1500)
        #expect(run.targets.map(\.localIdentifier) == ["1", "2"])
        #expect(!run.notes.hasPrefix("aborted"))
    }

    @Test("iOS deleted fewer than planned → only the deleted targets are listed")
    func partialDelete() {
        let run = PhoneDeleteRun.summarize([
            entry("phone-a", 0, .planned(targets: [target("1"), target("2")])),
            entry("phone-a", 1, .succeeded(localIdentifiers: ["2"], durationMs: nil)),
        ])[0]
        #expect(run.deletedCount == 1)
        #expect(run.durationMs == 0)
        #expect(run.targets.map(\.localIdentifier) == ["2"])
    }

    @Test("size-limit abort → aborted with reason in notes")
    func aborted() {
        let run = PhoneDeleteRun.summarize([
            entry("phone-a", 0, .aborted(reason: "Too many")),
        ])[0]
        #expect(run.outcome == .aborted(reason: "Too many"))
        #expect(run.deletedCount == 0)
        #expect(run.notes == "aborted · Too many")
    }

    @Test("declined system prompt → failed, targets kept for review")
    func failed() {
        let run = PhoneDeleteRun.summarize([
            entry("phone-a", 0, .planned(targets: [target("1")])),
            entry("phone-a", 1, .failed(localIdentifiers: ["1"], message: "Declined")),
        ])[0]
        #expect(run.outcome == .failed(message: "Declined"))
        #expect(run.deletedCount == 0)
        #expect(run.targets.count == 1)
        #expect(run.notes.hasPrefix("aborted · "))
    }

    @Test("planned with no outcome → unfinished")
    func unfinished() {
        let run = PhoneDeleteRun.summarize([
            entry("phone-a", 0, .planned(targets: [target("1")])),
        ])[0]
        #expect(run.outcome == .unfinished)
    }

    @Test("several runs → grouped by runId, newest first, rows in any order")
    func groupingAndOrder() {
        let runs = PhoneDeleteRun.summarize([
            entry("phone-new", 101, .succeeded(localIdentifiers: ["2"], durationMs: 10)),
            entry("phone-old", 0, .planned(targets: [target("1")])),
            entry("phone-new", 100, .planned(targets: [target("2")])),
            entry("phone-old", 1, .succeeded(localIdentifiers: ["1"], durationMs: 10)),
        ])
        #expect(runs.map(\.runId) == ["phone-new", "phone-old"])
        #expect(runs.allSatisfy { $0.outcome == .deleted })
        #expect(runs[0].startedAt == t0.addingTimeInterval(100))
    }
}
