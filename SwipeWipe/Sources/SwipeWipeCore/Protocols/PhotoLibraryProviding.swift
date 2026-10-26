//
//  PhotoLibraryProviding.swift
//  SwipeWipeCore
//
//  Production-grade Swift 6 protocol abstractions for PhotoKit access, permissions, and batch deletions.
//

import Foundation
import CoreGraphics

/// Normalized photo library privacy authorization status across platforms.
public enum PhotoAuthorizationStatus: String, Sendable, Codable, CaseIterable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case limited

    public var canReadPhotos: Bool {
        self == .authorized || self == .limited
    }

    public var canDeletePhotos: Bool {
        self == .authorized
    }
}

/// Structured result returned from batch deletion operations.
public struct BatchDeletionResult: Sendable, Equatable, Codable {
    public let success: Bool
    public let isUserCancelled: Bool
    public let deletedCount: Int
    public let reclaimedBytes: Int64
    public let failedIdentifiers: [String]
    public let errorMessage: String?

    public init(
        success: Bool,
        isUserCancelled: Bool = false,
        deletedCount: Int,
        reclaimedBytes: Int64,
        failedIdentifiers: [String] = [],
        errorMessage: String? = nil
    ) {
        self.success = success
        self.isUserCancelled = isUserCancelled
        self.deletedCount = deletedCount
        self.reclaimedBytes = reclaimedBytes
        self.failedIdentifiers = failedIdentifiers
        self.errorMessage = errorMessage
    }

    public static func userCancelled(failedIdentifiers: [String] = []) -> BatchDeletionResult {
        BatchDeletionResult(
            success: false,
            isUserCancelled: true,
            deletedCount: 0,
            reclaimedBytes: 0,
            failedIdentifiers: failedIdentifiers,
            errorMessage: "User cancelled system deletion prompt"
        )
    }
}

/// Observer protocol for external camera roll change notifications.
public protocol PhotoLibraryObserving: AnyObject, Sendable {
    func photoLibraryDidChange()
}

/// Thread-safe weak reference wrapper for `PhotoLibraryObserving` to prevent retain cycles.
public struct WeakPhotoLibraryObserver: @unchecked Sendable {
    public private(set) weak var value: (any PhotoLibraryObserving)?

    public init(_ value: any PhotoLibraryObserving) {
        self.value = value
    }
}

/// Primary abstraction for photo library ingestion, bucketing, clutter analysis, and batch deletion.
public protocol PhotoLibraryProviding: Sendable {
    /// The current authorization status without prompting the user.
    var authorizationStatus: PhotoAuthorizationStatus { get }

    /// Asynchronously requests photo library permissions from the user.
    func requestAuthorizationStatus() async -> PhotoAuthorizationStatus

    /// Deep link to system settings for privacy permission adjustment.
    func openSettings() async

    /// Triggers system limited library picker UI when status is `.limited`.
    func presentLimitedLibraryPicker() async

    /// Fetches all chronological monthly buckets with summary metadata.
    func fetchMonthlyBuckets() async throws -> [MonthlyBucket]

    /// Fetches all assets for a given month cohort.
    func fetchAssets(for bucketId: MonthIdentifier) async throws -> [PhotoAssetModel]

    /// Fetches flattened assets belonging to a clutter category.
    func fetchClutterCategory(_ category: ClutterCategoryType) async throws -> [PhotoAssetModel]

    /// Fetches organized clusters belonging to a clutter category.
    func fetchClutterClusters(_ category: ClutterCategoryType) async throws -> [ClutterCluster]

    /// Permanently deletes assets via the OS photo library confirmation batch API.
    func deleteAssets(withIdentifiers ids: [String]) async throws -> BatchDeletionResult

    /// Convenience overload returning boolean success for simpler consumer calls.
    func deleteAssets(withIdentifiers ids: [String]) async throws -> Bool

    /// Loads a displayable thumbnail image asynchronously.
    func loadThumbnail(for assetId: String, targetSize: CGSize) async throws -> CGImage?

    /// Registers a change notification observer.
    func addObserver(_ observer: PhotoLibraryObserving)

    /// Unregisters a change notification observer.
    func removeObserver(_ observer: PhotoLibraryObserving)
}

// Protocol extension providing default convenience implementations
public extension PhotoLibraryProviding {
    func requestAuthorization() async -> PhotoAuthorizationStatus {
        await requestAuthorizationStatus()
    }

    func deleteAssets(withIdentifiers ids: [String]) async throws -> Bool {
        let result = try await deleteAssets(withIdentifiers: ids)
        return result.success
    }

    func fetchClutterCategory(_ category: ClutterCategoryType) async throws -> [PhotoAssetModel] {
        let clusters = try await fetchClutterClusters(category)
        return clusters.flatMap(\.assets)
    }
}
