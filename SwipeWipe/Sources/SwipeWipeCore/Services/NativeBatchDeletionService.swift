//
//  NativeBatchDeletionService.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation
import os

/// Production batch deletion coordinator interfacing with `PhotoLibraryProviding`.
/// Implements non-destructive safety guards for Error 3072 (user cancellation).
public final class NativeBatchDeletionService: BatchDeletionServiceProtocol, @unchecked Sendable {

    private let photoProvider: any PhotoLibraryProviding
    private let logger = Logger(subsystem: "com.swipewipe.SwipeWipeCore", category: "NativeBatchDeletionService")

    public init(photoProvider: any PhotoLibraryProviding) {
        self.photoProvider = photoProvider
    }

    public struct PreDeletionCheckResult: Sendable, Equatable {
        public let totalCount: Int
        public let totalBytes: Int64
        public let favoriteCount: Int
        public let containsFavorites: Bool
        public let formattedSize: String
    }

    /// Evaluates staged items prior to deletion to provide double-confirmation details and favorite photo warnings.
    public func performPreDeletionCheck(items: [StagedAssetItem]) -> PreDeletionCheckResult {
        let totalBytes = items.reduce(Int64(0)) { $0 + $1.byteSize }
        let favorites = items.filter(\.isFavorite).count
        return PreDeletionCheckResult(
            totalCount: items.count,
            totalBytes: totalBytes,
            favoriteCount: favorites,
            containsFavorites: favorites > 0,
            formattedSize: SizeFormatter.formatDeterministic(bytes: totalBytes)
        )
    }

    public func executeBatchDeletion(items: [StagedAssetItem]) async -> DeletionOutcome {
        guard !items.isEmpty else {
            return .success(deletedCount: 0, reclaimedBytes: 0)
        }

        // Pre-deletion checks: Log warning if favorited assets are being deleted
        let favoriteCount = items.filter(\.isFavorite).count
        if favoriteCount > 0 {
            logger.warning("Pre-deletion safety alert: Batch deletion includes \(favoriteCount) user-favorited asset(s).")
        }

        let ids = items.map(\.id)
        let totalBytes = items.reduce(Int64(0)) { $0 + $1.byteSize }

        do {
            let result: BatchDeletionResult = try await photoProvider.deleteAssets(withIdentifiers: ids)
            if result.success {
                logger.info("Batch deletion successful: \(items.count) items, \(totalBytes) bytes.")
                return .success(deletedCount: items.count, reclaimedBytes: totalBytes)
            } else if result.isUserCancelled || (result.errorMessage?.contains("3072") == true) || (result.errorMessage?.lowercased().contains("cancel") == true) {
                logger.notice("Batch deletion cancelled by user (Result isUserCancelled or 3072). Preserving staged queue.")
                return .cancelledByUser
            } else {
                logger.error("Batch deletion failed: \(result.errorMessage ?? "Unknown error")")
                return .failed(reason: result.errorMessage ?? "Deletion failed")
            }
        } catch {
            let errString = "\(error)"
            let nsError = error as NSError
            if nsError.code == 3072 || errString.contains("3072") || errString.lowercased().contains("cancel") {
                logger.notice("User cancelled native batch deletion modal (Error code 3072). Preserving staged queue.")
                return .cancelledByUser
            } else if nsError.code == 3303 || errString.contains("3303") || errString.lowercased().contains("denied") {
                logger.error("Photo library write permission denied.")
                return .permissionDenied
            } else {
                logger.error("Batch deletion exception: \(error.localizedDescription)")
                return .failed(reason: error.localizedDescription)
            }
        }
    }
}
