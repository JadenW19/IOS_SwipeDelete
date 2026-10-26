//
//  BatchDeletionServiceProtocol.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation

/// Outcome of a batch deletion operation executed via the native system PhotoKit bridge.
public enum DeletionOutcome: Equatable, Sendable {
    case success(deletedCount: Int, reclaimedBytes: Int64)
    case cancelledByUser
    case failed(reason: String)
    case permissionDenied
}

/// Service protocol defining execution of batch deletions against the photo library.
public protocol BatchDeletionServiceProtocol: Sendable {
    /// Executes permanent deletion of staged items via native OS confirmation.
    func executeBatchDeletion(items: [StagedAssetItem]) async -> DeletionOutcome
}
