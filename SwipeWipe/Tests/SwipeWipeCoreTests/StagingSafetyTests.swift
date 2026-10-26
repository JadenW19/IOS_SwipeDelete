//
//  StagingSafetyTests.swift
//  SwipeWipeCoreTests
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//  Covers Requirement R3: Staged Deletion Queue, Size Calculation, Review Unstaging, Batch Deletion, Error 3072 Safety
//

import XCTest
import Foundation

// MARK: - Staging Safety Tests Suite

final class StagingSafetyTests: XCTestCase {

    // MARK: - Feature 14: Thread-Safe Staged Queue Store (F14)
    
    func testQueueEnqueueAndRunningCounts() {
        let store = StagedQueueStore()
        
        let item1 = StagedAssetItem(
            id: "asset-1",
            sourceBucketId: "2026-10",
            creationDate: Date(),
            mediaType: .photo,
            byteSize: 2_500_000
        )
        let item2 = StagedAssetItem(
            id: "asset-2",
            sourceBucketId: "2026-10",
            creationDate: Date(),
            mediaType: .video,
            byteSize: 50_000_000
        )
        
        let added1 = store.stageAsset(item1)
        let added2 = store.stageAsset(item2)
        
        XCTAssertTrue(added1)
        XCTAssertTrue(added2)
        
        let snapshot = store.snapshot
        XCTAssertEqual(snapshot.totalCount, 2)
        XCTAssertEqual(snapshot.totalByteSize, 52_500_000)
        XCTAssertEqual(snapshot.photoCount, 1)
        XCTAssertEqual(snapshot.videoCount, 1)
        XCTAssertEqual(snapshot.screenshotCount, 0)
    }
    
    func testDuplicateStagingIdempotency() {
        let store = StagedQueueStore()
        let item = StagedAssetItem(
            id: "dup-1",
            sourceBucketId: "2026-10",
            creationDate: Date(),
            mediaType: .photo,
            byteSize: 3_000_000
        )
        
        let firstAdd = store.stageAsset(item)
        let secondAdd = store.stageAsset(item) // Attempt duplicate
        
        XCTAssertTrue(firstAdd)
        XCTAssertFalse(secondAdd, "Duplicate staging must return false and be rejected")
        
        let snapshot = store.snapshot
        XCTAssertEqual(snapshot.totalCount, 1, "Count must remain 1")
        XCTAssertEqual(snapshot.totalByteSize, 3_000_000, "Byte size must not be added twice")
    }
    
    func testConcurrentStagingThreadSafety() {
        let store = StagedQueueStore()
        let queue = DispatchQueue(label: "test.concurrent.queue", attributes: .concurrent)
        let group = DispatchGroup()
        let itemCount = 500
        
        for i in 0..<itemCount {
            group.enter()
            queue.async {
                let item = StagedAssetItem(
                    id: "concurrent-\(i)",
                    sourceBucketId: "2026-10",
                    creationDate: Date(),
                    mediaType: .photo,
                    byteSize: 1_000_000
                )
                store.stageAsset(item)
                group.leave()
            }
        }
        
        group.wait()
        let snapshot = store.snapshot
        XCTAssertEqual(snapshot.totalCount, itemCount, "Thread-safe store must stage all 500 items without loss")
        XCTAssertEqual(snapshot.totalByteSize, Int64(itemCount * 1_000_000))
    }

    // MARK: - Feature 15: Non-Destructive Review & Space Formatting (F15)
    
    func testByteFormatterThresholds() {
        // Zero
        XCTAssertEqual(SizeFormatter.formatDeterministic(bytes: 0), "0 B")
        
        // Bytes (< 1,000)
        XCTAssertEqual(SizeFormatter.formatDeterministic(bytes: 750), "750 B")
        
        // Kilobytes (1,000 ... 999,999)
        XCTAssertEqual(SizeFormatter.formatDeterministic(bytes: 1_500), "1.5 KB")
        XCTAssertEqual(SizeFormatter.formatDeterministic(bytes: 450_000), "450 KB")
        
        // Megabytes (1,000,000 ... 999,999,999)
        XCTAssertEqual(SizeFormatter.formatDeterministic(bytes: 2_500_000), "2.5 MB")
        XCTAssertEqual(SizeFormatter.formatDeterministic(bytes: 85_000_000), "85.0 MB")
        
        // Gigabytes (>= 1,000,000,000)
        XCTAssertEqual(SizeFormatter.formatDeterministic(bytes: 1_840_000_000), "1.84 GB")
        XCTAssertEqual(SizeFormatter.formatDeterministic(bytes: 14_500_000_000), "14.5 GB")
        
        // Terabytes (>= 1,000,000,000,000)
        XCTAssertEqual(SizeFormatter.formatDeterministic(bytes: 2_500_000_000_000), "2.50 TB")
    }
    
    func testIndividualUnstagingRestoresStats() {
        let store = StagedQueueStore()
        let item1 = StagedAssetItem(id: "un-1", sourceBucketId: "b", creationDate: Date(), mediaType: .photo, byteSize: 4_000_000)
        let item2 = StagedAssetItem(id: "un-2", sourceBucketId: "b", creationDate: Date(), mediaType: .video, byteSize: 20_000_000)
        
        store.stageAsset(item1)
        store.stageAsset(item2)
        XCTAssertEqual(store.snapshot.totalCount, 2)
        XCTAssertEqual(store.snapshot.totalByteSize, 24_000_000)
        
        // Unstage item1
        let unstaged = store.unstageAsset(id: "un-1")
        XCTAssertNotNil(unstaged)
        XCTAssertEqual(unstaged?.id, "un-1")
        
        let snapshot = store.snapshot
        XCTAssertEqual(snapshot.totalCount, 1)
        XCTAssertEqual(snapshot.totalByteSize, 20_000_000)
        XCTAssertEqual(snapshot.photoCount, 0)
        XCTAssertEqual(snapshot.videoCount, 1)
        XCTAssertFalse(store.contains(id: "un-1"))
        XCTAssertTrue(store.contains(id: "un-2"))
    }
    
    func testBulkClearance() {
        let store = StagedQueueStore()
        for i in 1...10 {
            store.stageAsset(StagedAssetItem(id: "bulk-\(i)", sourceBucketId: "b", creationDate: Date(), mediaType: .photo, byteSize: 1_000_000))
        }
        XCTAssertEqual(store.snapshot.totalCount, 10)
        
        let cleared = store.clearAll()
        XCTAssertEqual(cleared.count, 10)
        
        let emptySnapshot = store.snapshot
        XCTAssertTrue(emptySnapshot.isEmpty)
        XCTAssertEqual(emptySnapshot.totalCount, 0)
        XCTAssertEqual(emptySnapshot.totalByteSize, 0)
        XCTAssertEqual(emptySnapshot.formattedSize, "0 B")
    }

    // MARK: - Feature 16: Native Batch Deletion Bridge (F16)
    
    func testEmptyQueueDeletionGuard() async {
        let mockProvider = MockPhotoProvider()
        let deletionService = NativeBatchDeletionService(photoProvider: mockProvider)
        
        let outcome = await deletionService.executeBatchDeletion(items: [])
        XCTAssertEqual(outcome, .success(deletedCount: 0, reclaimedBytes: 0))
        XCTAssertEqual(mockProvider.totalDeletionCalls, 0, "Provider must not be called when queue is empty")
    }
    
    func testSuccessfulBatchDeletionClearsItems() async {
        let mockProvider = MockPhotoProvider()
        mockProvider.deletionMode = .automaticSuccess
        let deletionService = NativeBatchDeletionService(photoProvider: mockProvider)
        
        let items = [
            StagedAssetItem(id: "del-1", sourceBucketId: "b", creationDate: Date(), mediaType: .photo, byteSize: 2_000_000),
            StagedAssetItem(id: "del-2", sourceBucketId: "b", creationDate: Date(), mediaType: .photo, byteSize: 3_000_000)
        ]
        
        let outcome = await deletionService.executeBatchDeletion(items: items)
        XCTAssertEqual(outcome, .success(deletedCount: 2, reclaimedBytes: 5_000_000))
        XCTAssertEqual(mockProvider.totalDeletionCalls, 1)
        XCTAssertEqual(mockProvider.recordedDeletionBatches.first, ["del-1", "del-2"])
    }

    // MARK: - Feature 17: System Error 3072 Cancellation Safety (F17)
    
    func testUserCancellationError3072Safety() async {
        let mockProvider = MockPhotoProvider()
        mockProvider.deletionMode = .simulateUserCancelled // Throws code 3072
        let deletionService = NativeBatchDeletionService(photoProvider: mockProvider)
        
        let store = StagedQueueStore()
        let item = StagedAssetItem(id: "cancel-guard", sourceBucketId: "b", creationDate: Date(), mediaType: .photo, byteSize: 5_000_000)
        store.stageAsset(item)
        
        let snapshotBefore = store.snapshot
        let outcome = await deletionService.executeBatchDeletion(items: snapshotBefore.items)
        
        // Assert: outcome is cancelledByUser
        XCTAssertEqual(outcome, .cancelledByUser)
        
        // Assert: Staged queue is 100% PRESERVED
        let snapshotAfter = store.snapshot
        XCTAssertEqual(snapshotAfter.totalCount, 1, "Queue must not lose items upon user cancellation")
        XCTAssertEqual(snapshotAfter.totalByteSize, 5_000_000, "Queue byte count must remain intact")
        XCTAssertTrue(store.contains(id: "cancel-guard"))
    }

    // MARK: - Feature 18: Favorite Asset Safeguards (F18)
    
    func testFavoriteAssetWarningTracking() {
        let store = StagedQueueStore()
        let favItem = StagedAssetItem(
            id: "fav-1",
            sourceBucketId: "b",
            creationDate: Date(),
            mediaType: .photo,
            byteSize: 4_000_000,
            isFavorite: true
        )
        let normalItem = StagedAssetItem(
            id: "norm-1",
            sourceBucketId: "b",
            creationDate: Date(),
            mediaType: .photo,
            byteSize: 2_000_000,
            isFavorite: false
        )
        
        store.stageAsset(favItem)
        store.stageAsset(normalItem)
        
        let snapshot = store.snapshot
        XCTAssertEqual(snapshot.totalCount, 2)
        XCTAssertEqual(snapshot.favoriteCount, 1, "Snapshot must detect 1 favorite staged")
        
        // Unstage favorite
        store.unstageAsset(id: "fav-1")
        XCTAssertEqual(store.snapshot.favoriteCount, 0, "Favorite count must decrement upon unstage")
    }
}
