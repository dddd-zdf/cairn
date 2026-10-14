import Foundation
import CairnCore
import CairnIOSCore

/// App-side wiring for the reverse direction (Immich trash → phone).
/// Hooks in `AppDependencies.swift`: `configureReverseDelete()` in
/// `bootstrap()`, and `ReverseDeleteController.shared.syncDidFinish()`
/// after a successful sync.
extension AppDependencies {

    func configureReverseDelete() {
        ReverseDeleteController.shared.host = ReverseDeleteController.Host(
            isReady: { [weak self] in
                guard let self else { return false }
                return await MainActor.run { self.immichClient != nil && self.journal != nil }
            },
            find: { [weak self] lookbackDays in
                guard let self else { throw CancellationError() }
                return try await self.computeServerTrashReview(lookbackDays: lookbackDays)
            },
            delete: { [weak self] candidates in
                guard let self else { return [] }
                return try await self.deleteServerTrashMatches(candidates)
            },
            keep: { [weak self] candidates in
                guard let self else { return }
                // Deduped: `exclude` builds a uniqueKeysWithValues
                // dictionary, and duplicate photos share checksums.
                let checksums = Array(Set(candidates.flatMap { $0.checksums.map(\.base64) })).sorted()
                let filenames = candidates.compactMap(\.serverAsset.originalFileName)
                let runId = "keep-on-phone-\(ISO8601DateFormatter().string(from: Date()))"
                let exclude = await MainActor.run { self.model.actions.exclude }
                try? await exclude(checksums, filenames, runId)
            }
        )
    }

    private func computeServerTrashReview(lookbackDays: Int) async throws -> ServerTrashReview {
        guard let client = immichClient,
              let observed = observedStore,
              let exclusions = exclusionStore,
              let journal else {
            // Not "nothing waiting": a fake empty result would clear the
            // pending count and reminder.
            throw LocalDeleteError.failed("cairn isn't connected to Immich yet.")
        }
        let scope = model.settings.indexingScope
        let since = Date().addingTimeInterval(-Double(lookbackDays) * 86_400)
        let trashed = try await client.listTrashedAssets(trashedAfter: since)
        guard !trashed.isEmpty else {
            return ServerTrashReview(candidates: [], lookbackDays: lookbackDays)
        }

        let liveIds = await Task.detached(priority: .userInitiated) {
            PhotoKitLocalAssetDeleter.liveUserLibraryIdentifiers()
        }.value
        let allHashes = try await localHashStore.snapshot()
        let firstObserved = (try? await editRetirementStore?.snapshot()) ?? [:]
        let imputed = (try? await localHashStore.imputedIdentifiers()) ?? []
        let inPurview: Set<Checksum>
        switch scope {
        case .fullLibrary:
            inPurview = try await observed.snapshot()
        case .selectedAlbums(let albumIds):
            inPurview = Set(try await observed.snapshotWithTags()
                .filter { !$0.value.isDisjoint(with: albumIds) }
                .keys)
        }
        let excluded = Set(try await exclusions.snapshot().keys)
        // Archive included: a cairn trash older than the live journal's
        // protect window can still be in Immich's trash.
        let journalEntries = ((try? await journal.readArchive()) ?? []) + ((try? await journal.readAll()) ?? [])
        let trashedByCairn = Set(JournalReader.recentlyTrashedChecksums(in: journalEntries, withinDays: 60).keys)

        // Filtering + matching walk the whole hash cache; keep it off the
        // main actor.
        let match = await Task.detached(priority: .userInitiated) {
            ServerTrashMatcher.match(ServerTrashMatchInput(
                trashedServerAssets: trashed,
                liveLocalHashes: allHashes.filter { liveIds.contains($0.key) },
                firstObserved: firstObserved,
                imputedIdentifiers: imputed,
                inPurview: inPurview,
                excluded: excluded,
                trashedByCairn: trashedByCairn
            ))
        }.value
        return ServerTrashReview(
            candidates: match.candidates,
            skipped: match.skipped,
            trashedOnServer: trashed.count,
            lookbackDays: lookbackDays,
            liveLibraryCount: liveIds.count
        )
    }

    private func deleteServerTrashMatches(_ candidates: [LocalDeleteCandidate]) async throws -> [String] {
        guard let journal, !candidates.isEmpty else { return [] }
        let liveCount = await Task.detached(priority: .userInitiated) {
            PhotoKitLocalAssetDeleter.liveUserLibraryIdentifiers().count
        }.value
        let localJournal = LocalDeleteJournal(
            path: journal.path.deletingLastPathComponent().appending(path: LocalDeleteJournal.fileName)
        )
        let runId = "phone-\(ISO8601DateFormatter().string(from: Date()))-\(UUID().uuidString.prefix(8))"
        let summary = try await LocalDeleteOrchestrator(deleter: PhotoKitLocalAssetDeleter(), journal: localJournal).run(
            runId: runId,
            candidates: candidates,
            liveLibraryCount: liveCount
        )
        if let reason = summary.abortReason {
            throw LocalDeleteError.failed(reason)
        }
        return summary.deletedLocalIdentifiers
    }
}
