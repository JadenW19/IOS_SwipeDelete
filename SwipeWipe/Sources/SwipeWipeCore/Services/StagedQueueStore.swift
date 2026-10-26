//
//  StagedQueueStore.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation

/// Thread-safe in-memory store maintaining the review queue of staged photo deletions.
/// Guarantees O(1) duplicate detection, running size calculations, and individual unstaging.
public final class StagedQueueStore: StagedQueueStoreProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var orderedItems: [StagedAssetItem] = []
    private var itemMap: [String: StagedAssetItem] = [:]

    private var runningByteSize: Int64 = 0
    private var runningPhotoCount: Int = 0
    private var runningVideoCount: Int = 0
    private var runningScreenshotCount: Int = 0
    private var runningFavoriteCount: Int = 0

    public init() {}

    public var snapshot: StagedQueueSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let formatted = SizeFormatter.formatDeterministic(bytes: runningByteSize)
        return StagedQueueSnapshot(
            items: orderedItems,
            totalCount: orderedItems.count,
            totalByteSize: runningByteSize,
            photoCount: runningPhotoCount,
            videoCount: runningVideoCount,
            screenshotCount: runningScreenshotCount,
            favoriteCount: runningFavoriteCount,
            isEmpty: orderedItems.isEmpty,
            formattedSize: formatted
        )
    }

    public func stageAsset(_ item: StagedAssetItem) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Idempotency: Reject duplicate staging attempts
        if itemMap[item.id] != nil {
            return false
        }

        itemMap[item.id] = item
        orderedItems.append(item)

        // Update running aggregates
        runningByteSize += item.byteSize
        if item.isFavorite { runningFavoriteCount += 1 }

        switch item.mediaType {
        case .photo:
            runningPhotoCount += 1
        case .video:
            runningVideoCount += 1
        case .screenshot:
            runningScreenshotCount += 1
        case .livePhoto:
            runningPhotoCount += 1
        }

        return true
    }

    public func unstageAsset(id: String) -> StagedAssetItem? {
        lock.lock()
        defer { lock.unlock() }

        guard let item = itemMap.removeValue(forKey: id) else {
            return nil
        }

        if let index = orderedItems.firstIndex(where: { $0.id == id }) {
            orderedItems.remove(at: index)
        }

        // Decrement running aggregates
        runningByteSize = max(0, runningByteSize - item.byteSize)
        if item.isFavorite { runningFavoriteCount = max(0, runningFavoriteCount - 1) }

        switch item.mediaType {
        case .photo:
            runningPhotoCount = max(0, runningPhotoCount - 1)
        case .video:
            runningVideoCount = max(0, runningVideoCount - 1)
        case .screenshot:
            runningScreenshotCount = max(0, runningScreenshotCount - 1)
        case .livePhoto:
            runningPhotoCount = max(0, runningPhotoCount - 1)
        }

        return item
    }

    public func clearAll() -> [StagedAssetItem] {
        lock.lock()
        defer { lock.unlock() }

        let items = orderedItems
        orderedItems.removeAll()
        itemMap.removeAll()

        runningByteSize = 0
        runningPhotoCount = 0
        runningVideoCount = 0
        runningScreenshotCount = 0
        runningFavoriteCount = 0

        return items
    }

    public func contains(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return itemMap[id] != nil
    }

    public func getStagedItem(id: String) -> StagedAssetItem? {
        lock.lock()
        defer { lock.unlock() }
        return itemMap[id]
    }

    public var stagedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return orderedItems.count
    }

    public var totalReclaimedBytes: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return runningByteSize
    }

    public func enqueue(asset: PhotoAssetModel) {
        let item = StagedAssetItem(photoAsset: asset)
        _ = stageAsset(item)
    }

    @discardableResult
    public func remove(assetId: String) -> PhotoAssetModel? {
        unstageAsset(id: assetId)?.photoAsset
    }

    public func clear() {
        _ = clearAll()
    }

    public func allStagedAssets() -> [PhotoAssetModel] {
        lock.lock()
        defer { lock.unlock() }
        return orderedItems.map(\.photoAsset)
    }
}
