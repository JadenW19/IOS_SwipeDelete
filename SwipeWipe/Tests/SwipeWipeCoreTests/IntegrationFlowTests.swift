//
//  IntegrationFlowTests.swift
//  SwipeWipeCoreTests
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//  Covers End-to-End Integration User Workflows (Requirements R1, R2, R3, R4)
//

import XCTest
import Foundation

// MARK: - Integration Flow Tests Suite

final class IntegrationFlowTests: XCTestCase {

    // MARK: - Workflow 1: End-to-End Month Cleaning Journey
    
    func testEndToEndMonthCleaningFlow() async throws {
        // 1. Ingestion: Mock 5 photos in "October 2026"
        let mockProvider = MockPhotoProvider()
        mockProvider.stubbedAuthorizationStatus = .authorized
        
        let monthId = MonthIdentifier(year: 2026, month: 10)
        let initialAssets = (1...5).map { i in
            PhotoAssetModel(
                id: "oct-\(i)",
                localIdentifier: "ph-oct-\(i)",
                creationDate: Date(),
                estimatedByteSize: Int64(i * 1_000_000)
            )
        }
        mockProvider.stubbedAssets["2026-10"] = initialAssets
        
        let fetchedAssets = try await mockProvider.fetchAssets(for: monthId)
        XCTAssertEqual(fetchedAssets.count, 5)
        
        // 2. Swiping Interaction:
        //    - Swipe right (Retain) on assets 1, 2, 3
        //    - Swipe left (Stage Delete) on assets 4, 5
        let stagingStore = StagedQueueStore()
        var deck = fetchedAssets
        var retained: [PhotoAssetModel] = []
        var undoHistory: [SwipeAction] = []
        
        // Swipe asset 1 right
        let a1 = deck.removeFirst()
        retained.append(a1)
        undoHistory.append(SwipeAction(assetId: a1.id, direction: .retain, timestamp: Date()))
        
        // Swipe asset 2 right
        let a2 = deck.removeFirst()
        retained.append(a2)
        undoHistory.append(SwipeAction(assetId: a2.id, direction: .retain, timestamp: Date()))
        
        // Swipe asset 3 right
        let a3 = deck.removeFirst()
        retained.append(a3)
        undoHistory.append(SwipeAction(assetId: a3.id, direction: .retain, timestamp: Date()))
        
        // Swipe asset 4 left (Stage)
        let a4 = deck.removeFirst()
        stagingStore.stageAsset(StagedAssetItem(id: a4.id, sourceBucketId: "2026-10", creationDate: a4.creationDate, mediaType: .photo, byteSize: a4.estimatedByteSize))
        undoHistory.append(SwipeAction(assetId: a4.id, direction: .stageDelete, timestamp: Date()))
        
        // Swipe asset 5 left (Stage)
        let a5 = deck.removeFirst()
        stagingStore.stageAsset(StagedAssetItem(id: a5.id, sourceBucketId: "2026-10", creationDate: a5.creationDate, mediaType: .photo, byteSize: a5.estimatedByteSize))
        undoHistory.append(SwipeAction(assetId: a5.id, direction: .stageDelete, timestamp: Date()))
        
        // Verify deck is empty (all 5 processed)
        XCTAssertTrue(deck.isEmpty, "Deck should be empty after swiping all 5 cards")
        XCTAssertEqual(retained.count, 3)
        XCTAssertEqual(stagingStore.snapshot.totalCount, 2)
        XCTAssertEqual(stagingStore.snapshot.totalByteSize, 9_000_000) // 4MB + 5MB
        
        // 3. Staging Review & Batch Deletion
        let deletionService = NativeBatchDeletionService(photoProvider: mockProvider)
        mockProvider.deletionMode = .automaticSuccess
        
        let outcome = await deletionService.executeBatchDeletion(items: stagingStore.snapshot.items)
        XCTAssertEqual(outcome, .success(deletedCount: 2, reclaimedBytes: 9_000_000))
        
        // Clear store upon verified success
        _ = stagingStore.clearAll()
        XCTAssertTrue(stagingStore.snapshot.isEmpty)
        XCTAssertEqual(mockProvider.deletedAssetIdentifiers, ["oct-4", "oct-5"])
    }

    // MARK: - Workflow 2: Rapid Swiping, Interleaved Undos, and Empty State
    
    func testSwipingWithInterleavedUndosFlow() {
        var deck = (1...6).map { "card-\($0)" }
        var retained: [String] = []
        var staged: [String] = []
        var undoStack: [SwipeAction] = []
        
        // Swipe 1 right (keep)
        let c1 = deck.removeFirst()
        retained.append(c1)
        undoStack.append(SwipeAction(assetId: c1, direction: .retain, timestamp: Date()))
        
        // Swipe 2 left (stage)
        let c2 = deck.removeFirst()
        staged.append(c2)
        undoStack.append(SwipeAction(assetId: c2, direction: .stageDelete, timestamp: Date()))
        
        // Swipe 3 left (stage)
        let c3 = deck.removeFirst()
        staged.append(c3)
        undoStack.append(SwipeAction(assetId: c3, direction: .stageDelete, timestamp: Date()))
        
        XCTAssertEqual(deck.count, 3)
        XCTAssertEqual(undoStack.count, 3)
        
        // User realizes accidental swipe on card-3 -> Undo!
        let undone3 = undoStack.removeLast()
        XCTAssertEqual(undone3.assetId, "card-3")
        staged.removeAll { $0 == undone3.assetId }
        deck.insert(undone3.assetId, at: 0)
        
        // User realizes card-2 was also a mistake -> Undo!
        let undone2 = undoStack.removeLast()
        XCTAssertEqual(undone2.assetId, "card-2")
        staged.removeAll { $0 == undone2.assetId }
        deck.insert(undone2.assetId, at: 0)
        
        // Deck order must be: card-2, card-3, card-4, card-5, card-6
        XCTAssertEqual(deck, ["card-2", "card-3", "card-4", "card-5", "card-6"])
        XCTAssertEqual(staged.count, 0)
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(undoStack.count, 1)
    }

    // MARK: - Workflow 3: Clutter Ingestion, Unstaging 1 Item, and Batch Delete Remainder
    
    func testClutterPurgeWithGranularUnstageFlow() async {
        let store = StagedQueueStore()
        
        // User stages 4 screenshot clutter assets
        let shot1 = StagedAssetItem(id: "s1", sourceBucketId: "clutter", creationDate: Date(), mediaType: .screenshot, byteSize: 1_200_000)
        let shot2 = StagedAssetItem(id: "s2", sourceBucketId: "clutter", creationDate: Date(), mediaType: .screenshot, byteSize: 1_300_000)
        let shot3 = StagedAssetItem(id: "s3", sourceBucketId: "clutter", creationDate: Date(), mediaType: .screenshot, byteSize: 1_100_000)
        let shot4 = StagedAssetItem(id: "s4", sourceBucketId: "clutter", creationDate: Date(), mediaType: .screenshot, byteSize: 1_400_000)
        
        store.stageAsset(shot1)
        store.stageAsset(shot2)
        store.stageAsset(shot3)
        store.stageAsset(shot4)
        
        XCTAssertEqual(store.snapshot.totalCount, 4)
        XCTAssertEqual(store.snapshot.totalByteSize, 5_000_000)
        
        // In the review drawer, user notices shot2 should NOT be deleted -> Unstage it!
        let unstaged = store.unstageAsset(id: "s2")
        XCTAssertNotNil(unstaged)
        XCTAssertEqual(store.snapshot.totalCount, 3)
        XCTAssertEqual(store.snapshot.totalByteSize, 3_700_000)
        
        // User commits deletion on remaining 3
        let mockProvider = MockPhotoProvider()
        let deletionService = NativeBatchDeletionService(photoProvider: mockProvider)
        let outcome = await deletionService.executeBatchDeletion(items: store.snapshot.items)
        
        XCTAssertEqual(outcome, .success(deletedCount: 3, reclaimedBytes: 3_700_000))
        XCTAssertEqual(mockProvider.recordedDeletionBatches.first, ["s1", "s3", "s4"])
        XCTAssertFalse(mockProvider.recordedDeletionBatches.first!.contains("s2"))
    }

    // MARK: - Workflow 4: Cancellation Recovery Flow (Error 3072)
    
    func testCancellationAndReattemptFlow() async {
        let store = StagedQueueStore()
        let itemA = StagedAssetItem(id: "itemA", sourceBucketId: "b", creationDate: Date(), mediaType: .photo, byteSize: 10_000_000)
        let itemB = StagedAssetItem(id: "itemB", sourceBucketId: "b", creationDate: Date(), mediaType: .photo, byteSize: 15_000_000)
        store.stageAsset(itemA)
        store.stageAsset(itemB)
        
        let mockProvider = MockPhotoProvider()
        let deletionService = NativeBatchDeletionService(photoProvider: mockProvider)
        
        // 1st attempt: User taps Cancel on system alert (error code 3072)
        mockProvider.deletionMode = .simulateUserCancelled
        let outcome1 = await deletionService.executeBatchDeletion(items: store.snapshot.items)
        XCTAssertEqual(outcome1, .cancelledByUser)
        
        // Assert queue remains untouched
        XCTAssertEqual(store.snapshot.totalCount, 2)
        XCTAssertEqual(store.snapshot.totalByteSize, 25_000_000)
        
        // 2nd attempt: User opens review again and taps Delete -> Confirms system alert
        mockProvider.deletionMode = .automaticSuccess
        let outcome2 = await deletionService.executeBatchDeletion(items: store.snapshot.items)
        XCTAssertEqual(outcome2, .success(deletedCount: 2, reclaimedBytes: 25_000_000))
        
        _ = store.clearAll()
        XCTAssertTrue(store.snapshot.isEmpty)
    }
}
