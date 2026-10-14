import Foundation

extension ImmichClient {

    /// Assets moved to Immich's trash at or after `trashedAfter`, for the
    /// reverse (Immich → phone) direction. Only primaries: `timeline` and
    /// `archive` are iterated; `hidden` (Live Photo motion videos) isn't
    /// needed because the still carries the signal, and `locked` needs an
    /// elevated session.
    ///
    /// Uses the flat `trashedAfter` / `withDeleted` / `visibility` fields
    /// like the rest of this client. Immich 3.2 deprecated them in favor
    /// of `filter.trashedAt` + cursor paging, but they still work on 3.3
    /// and the new shape doesn't exist before 3.2. Rows with
    /// `isTrashed == false` are dropped defensively.
    public func listTrashedAssets(trashedAfter: Date, pageSize: Int = 1000) async throws -> [ServerAsset] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let since = formatter.string(from: trashedAfter)
        var out: [ServerAsset] = []
        var seen: Set<String> = []
        for visibility in [AssetVisibility.timeline, .archive] {
            var page = 1
            while true {
                try Task.checkCancellation()
                let body: [String: Any] = [
                    "page": page,
                    "size": pageSize,
                    "withDeleted": true,
                    "trashedAfter": since,
                    "withExif": false,
                    "visibility": visibility.rawValue,
                ]
                let result: SearchResponseDTO = try await postJSON(path: "search/metadata", jsonObject: body)
                for asset in result.assets.items.map(\.asServerAsset) where asset.isTrashed && !seen.contains(asset.id) {
                    out.append(asset)
                    seen.insert(asset.id)
                }
                guard let nextString = result.assets.nextPage, let nextPage = Int(nextString) else { break }
                page = nextPage
            }
        }
        return out
    }
}
