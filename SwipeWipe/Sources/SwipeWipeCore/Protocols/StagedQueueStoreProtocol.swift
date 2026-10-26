//
//  StagedQueueStoreProtocol.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation

/// Read-only snapshot of the staged queue state at a discrete point in time.
public struct StagedQueueSnapshot: Sendable, Equatable {
    public let items: [StagedAssetItem]
    public let totalCount: Int
    public let totalByteSize: Int64
    public let photoCount: Int
    public let videoCount: Int
    public let screenshotCount: Int
    public let favoriteCount: Int
    public let isEmpty: Bool
    public let formattedSize: String

    public init(
        items: [StagedAssetItem] = [],
        totalCount: Int = 0,
        totalByteSize: Int64 = 0,
        photoCount: Int = 0,
        videoCount: Int = 0,
        screenshotCount: Int = 0,
        favoriteCount: Int = 0,
        isEmpty: Bool = true,
        formattedSize: String = "0 B"
    ) {
        self.items = items
        self.totalCount = totalCount
        self.totalByteSize = totalByteSize
        self.photoCount = photoCount
        self.videoCount = videoCount
        self.screenshotCount = screenshotCount
        self.favoriteCount = favoriteCount
        self.isEmpty = isEmpty
        self.formattedSize = formattedSize
    }
}

/// Primary protocol defining thread-safe staged queue storage and running aggregates.
public protocol StagedQueueStoreProtocol: Sendable {
    /// Generates an immutable snapshot of current queue contents and running counts.
    var snapshot: StagedQueueSnapshot { get }

    /// Current count of staged assets in the queue.
    var stagedCount: Int { get }

    /// Total estimated byte size of all staged items.
    var totalReclaimedBytes: Int64 { get }

    /// Enqueues an asset for deletion review. Returns `true` if enqueued, `false` if duplicate.
    @discardableResult
    func stageAsset(_ item: StagedAssetItem) -> Bool

    /// Unstages an asset by ID, restoring it to the library. Returns the unstaged item if found.
    @discardableResult
    func unstageAsset(id: String) -> StagedAssetItem?

    /// Clears all staged items from the queue. Returns the cleared items.
    @discardableResult
    func clearAll() -> [StagedAssetItem]

    /// Checks if an asset identifier is currently staged.
    func contains(id: String) -> Bool

    /// Retrieves an asset by ID if currently staged.
    func getStagedItem(id: String) -> StagedAssetItem?

    /// Enqueues a PhotoAssetModel directly into the review queue.
    func enqueue(asset: PhotoAssetModel)

    /// Removes an asset by ID and returns its PhotoAssetModel if present.
    @discardableResult
    func remove(assetId: String) -> PhotoAssetModel?

    /// Clears all items from the queue.
    func clear()

    /// Returns all currently staged assets mapped to PhotoAssetModel.
    func allStagedAssets() -> [PhotoAssetModel]
}

// MARK: - Default Protocol Convenience Extensions

public extension StagedQueueStoreProtocol {
    var stagedCount: Int {
        snapshot.totalCount
    }

    var totalReclaimedBytes: Int64 {
        snapshot.totalByteSize
    }

    func enqueue(asset: PhotoAssetModel) {
        let item = StagedAssetItem(photoAsset: asset)
        _ = stageAsset(item)
    }

    @discardableResult
    func remove(assetId: String) -> PhotoAssetModel? {
        unstageAsset(id: assetId)?.photoAsset
    }

    func clear() {
        _ = clearAll()
    }

    func allStagedAssets() -> [PhotoAssetModel] {
        snapshot.items.map(\.photoAsset)
    }
}
