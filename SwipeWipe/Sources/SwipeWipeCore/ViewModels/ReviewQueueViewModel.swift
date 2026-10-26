//
//  ReviewQueueViewModel.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation
import Combine

/// Coordinator for the non-destructive review drawer and native batch deletion workflow.
@MainActor
public final class ReviewQueueViewModel: ObservableObject {

    @Published public private(set) var snapshot: StagedQueueSnapshot
    @Published public var isPresentingConfirmationDialog: Bool = false
    @Published public var isDeleting: Bool = false
    @Published public var lastOutcome: DeletionOutcome?
    @Published public var errorMessage: String?

    public let stagingStore: any StagedQueueStoreProtocol
    public let deletionService: any BatchDeletionServiceProtocol
    public let haptics: any HapticFeedbackServiceProtocol

    public init(
        stagingStore: any StagedQueueStoreProtocol = StagedQueueStore(),
        deletionService: any BatchDeletionServiceProtocol,
        haptics: any HapticFeedbackServiceProtocol = HapticFeedbackService()
    ) {
        self.stagingStore = stagingStore
        self.deletionService = deletionService
        self.haptics = haptics
        self.snapshot = stagingStore.snapshot
    }

    public enum UnstageDestination: Sendable {
        case retained
        case deck
    }

    /// Callback fired when an item is unstaged and restored to the Kept (Retained) list.
    public var onRestoreToRetained: ((StagedAssetItem) -> Void)?

    /// Callback fired when an item is unstaged and restored to the active Swipe Deck.
    public var onRestoreToDeck: ((StagedAssetItem) -> Void)?

    public var stagedItems: [StagedAssetItem] {
        snapshot.items
    }

    public var totalCount: Int {
        snapshot.totalCount
    }

    public var formattedReclaimedSpace: String {
        snapshot.formattedSize
    }

    public var totalReclaimedBytes: Int64 {
        snapshot.totalByteSize
    }

    public var hasFavorites: Bool {
        snapshot.favoriteCount > 0
    }

    public var favoriteCount: Int {
        snapshot.favoriteCount
    }

    public func refresh() {
        self.snapshot = stagingStore.snapshot
    }

    /// Requests presentation of the in-app double-confirmation modal.
    public func requestDeletionConfirmation() {
        self.isPresentingConfirmationDialog = true
    }

    /// Dismisses the in-app confirmation modal without executing deletion.
    public func dismissConfirmation() {
        self.isPresentingConfirmationDialog = false
    }

    /// Unstages an asset and restores it to either Retained (Keep) or Deck based on user intent.
    @discardableResult
    public func unstageAsset(id: String, destination: UnstageDestination = .retained) -> StagedAssetItem? {
        guard let unstaged = stagingStore.unstageAsset(id: id) else {
            return nil
        }
        refresh()
        haptics.triggerSelection()

        switch destination {
        case .retained:
            onRestoreToRetained?(unstaged)
        case .deck:
            onRestoreToDeck?(unstaged)
        }

        return unstaged
    }

    /// Convenience overload unstaging asset specifically to the active swipe deck.
    @discardableResult
    public func unstageToDeck(id: String) -> StagedAssetItem? {
        unstageAsset(id: id, destination: .deck)
    }

    /// Convenience overload unstaging asset specifically to retained/keep state.
    @discardableResult
    public func unstageToRetained(id: String) -> StagedAssetItem? {
        unstageAsset(id: id, destination: .retained)
    }

    public func clearAll() {
        _ = stagingStore.clearAll()
        refresh()
        haptics.triggerSelection()
    }

    /// Commits the batch deletion of all currently staged items.
    @discardableResult
    public func commitBatchDeletion() async -> DeletionOutcome {
        await executeBatchDeletion()
    }

    @discardableResult
    public func executeBatchDeletion() async -> DeletionOutcome {
        guard !snapshot.items.isEmpty else {
            let emptyOutcome = DeletionOutcome.success(deletedCount: 0, reclaimedBytes: 0)
            self.lastOutcome = emptyOutcome
            return emptyOutcome
        }

        self.isDeleting = true
        self.errorMessage = nil

        let itemsToDelete = snapshot.items
        let outcome = await deletionService.executeBatchDeletion(items: itemsToDelete)
        self.isDeleting = false
        self.lastOutcome = outcome

        switch outcome {
        case .success:
            _ = stagingStore.clearAll()
            refresh()
            haptics.triggerSuccess()

        case .cancelledByUser:
            // Error 3072 safety: Preserves all staged items in queue
            refresh()
            haptics.triggerSelection()

        case .failed(let reason):
            self.errorMessage = reason
            haptics.triggerNotification(type: .error)

        case .permissionDenied:
            self.errorMessage = "Photo library write permissions are denied. Please enable full photo access in Settings."
            haptics.triggerNotification(type: .error)
        }

        return outcome
    }
}
