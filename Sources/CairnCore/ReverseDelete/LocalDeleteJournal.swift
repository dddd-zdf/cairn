import Foundation

/// Append-only JSONL log of phone-side deletes (the reverse direction).
/// Deliberately separate from `DeletionJournal`: its own file, its own
/// event type, so cairn's trash-run journal, Runs tab, and rotation are
/// untouched. Lives next to `deletion-journal.jsonl` in the same
/// per-account directory.
public actor LocalDeleteJournal {
    public nonisolated let path: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public static let fileName = "phone-delete-journal.jsonl"

    public init(path: URL) {
        self.path = path
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    public func append(_ entry: LocalDeleteJournalEntry) throws {
        var line = try encoder.encode(entry)
        line.append(0x0A)
        let fm = FileManager.default
        if !fm.fileExists(atPath: path.path) {
            fm.createFile(atPath: path.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.close()
    }

    /// Undecodable rows are skipped.
    public func readAll() throws -> [LocalDeleteJournalEntry] {
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        let text = String(decoding: try Data(contentsOf: path), as: UTF8.self)
        return text.split(whereSeparator: \.isNewline).compactMap {
            try? decoder.decode(LocalDeleteJournalEntry.self, from: Data($0.utf8))
        }
    }
}

public struct LocalDeleteJournalEntry: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let runId: String
    public let event: Event

    public init(timestamp: Date = Date(), runId: String, event: Event) {
        self.timestamp = timestamp
        self.runId = runId
        self.event = event
    }

    public enum Event: Codable, Sendable, Equatable {
        /// Write-ahead record of the phone assets about to be deleted.
        case planned(targets: [Target])
        /// iOS accepted the delete; ids moved to Recently Deleted.
        case succeeded(localIdentifiers: [String], durationMs: Int?)
        /// The delete failed or the user declined the system prompt.
        case failed(localIdentifiers: [String], message: String)
        /// Size limit refused the batch before PhotoKit was called.
        case aborted(reason: String)
    }

    /// One phone asset at plan time, plus the Immich asset whose trashing
    /// triggered it.
    public struct Target: Codable, Sendable, Equatable {
        public let localIdentifier: String
        public let checksums: [String]
        public let serverAssetId: String
        public let originalFileName: String?
        public let fileCreatedAt: Date?

        public init(
            localIdentifier: String,
            checksums: [String],
            serverAssetId: String,
            originalFileName: String? = nil,
            fileCreatedAt: Date? = nil
        ) {
            self.localIdentifier = localIdentifier
            self.checksums = checksums
            self.serverAssetId = serverAssetId
            self.originalFileName = originalFileName
            self.fileCreatedAt = fileCreatedAt
        }
    }
}
