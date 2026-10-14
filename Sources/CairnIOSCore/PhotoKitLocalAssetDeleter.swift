import Foundation
import CairnCore

#if canImport(Photos)
import Photos

/// PhotoKit side of the reverse direction. One `performChanges` call so
/// iOS shows a single "Allow cairn to delete N photos?" prompt; deleted
/// items land in Recently Deleted for 30 days.
public struct PhotoKitLocalAssetDeleter: LocalAssetDeleter {

    public init() {}

    public func deleteAssets(localIdentifiers: [String]) async throws -> [String] {
        let ids = Self.deletableIdentifiers(localIdentifiers)
        guard !ids.isEmpty else { return [] }
        do {
            // Re-fetch inside the block so only Sendable ids cross into it.
            try await PHPhotoLibrary.shared().performChanges {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch {
            let ns = error as NSError
            if ns.domain == PHPhotosErrorDomain, ns.code == PHPhotosError.Code.userCancelled.rawValue {
                throw LocalDeleteError.userCancelled
            }
            throw LocalDeleteError.failed(error.localizedDescription)
        }
        return ids
    }

    /// Ids still in the library, owned by the user (not Shared Library or
    /// iTunes-synced), and deletable. Order follows the input.
    nonisolated static func deletableIdentifiers(_ ids: [String]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let opts = PHFetchOptions()
        opts.includeHiddenAssets = true
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: opts)
        var ok: Set<String> = []
        fetch.enumerateObjects { asset, _, _ in
            if asset.sourceType == .typeUserLibrary, asset.canPerform(.delete) {
                ok.insert(asset.localIdentifier)
            }
        }
        return ids.filter { ok.contains($0) }
    }

    /// Live user-library ids, hidden included. The reverse direction only
    /// considers these.
    public nonisolated static func liveUserLibraryIdentifiers() -> Set<String> {
        PhotoKitPersistentChangeReconciler.enumerateLiveLocalIdentifiers(
            includeHiddenAssets: true,
            sourceTypes: [.typeUserLibrary]
        )
    }
}
#endif
