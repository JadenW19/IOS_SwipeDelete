//
//  LibraryViewModel.swift
//  SwipeWipeCore
//
//  Production-grade SwiftUI ViewModel coordinating permission lifecycle,
//  chronological monthly buckets, clutter categories, and external changes.
//

import Foundation
import Combine
import os

/// Main-actor coordinator managing camera roll ingestion state, permissions, and collection navigation.
@MainActor
public final class LibraryViewModel: ObservableObject, PhotoLibraryObserving {

    private let logger = Logger(subsystem: "com.swipewipe.SwipeWipeCore", category: "LibraryViewModel")
    public let photoProvider: any PhotoLibraryProviding

    // MARK: - Published State

    @Published public private(set) var authorizationStatus: PhotoAuthorizationStatus = .notDetermined
    @Published public private(set) var monthlyBuckets: [MonthlyBucket] = []
    @Published public private(set) var selectedBucket: MonthlyBucket? = nil
    @Published public private(set) var selectedBucketAssets: [PhotoAssetModel] = []

    @Published public private(set) var selectedClutterCategory: ClutterCategoryType? = nil
    @Published public private(set) var selectedClutterClusters: [ClutterCluster] = []
    @Published public private(set) var selectedClutterAssets: [PhotoAssetModel] = []

    @Published public private(set) var clutterSummary: [ClutterCategoryType: Int] = [:]
    @Published public private(set) var clutterByteSummary: [ClutterCategoryType: Int64] = [:]

    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    public struct ClutterCategorySummary: Sendable, Equatable {
        public let assetCount: Int
        public let totalByteSize: Int64
    }

    public var clutterCategories: [ClutterCategoryType: ClutterCategorySummary] {
        var result: [ClutterCategoryType: ClutterCategorySummary] = [:]
        for category in ClutterCategoryType.allCases {
            result[category] = ClutterCategorySummary(
                assetCount: clutterSummary[category] ?? 0,
                totalByteSize: clutterByteSummary[category] ?? 0
            )
        }
        return result
    }

    // MARK: - Initialization & Teardown

    public init(photoProvider: any PhotoLibraryProviding) {
        self.photoProvider = photoProvider
        self.authorizationStatus = photoProvider.authorizationStatus
        photoProvider.addObserver(self)

        // Automatically load if already authorized or limited
        if authorizationStatus.canReadPhotos {
            Task {
                await loadLibrary()
            }
        }
    }

    deinit {
        photoProvider.removeObserver(self)
    }

    // MARK: - Permission Lifecycle

    /// Checks the current authorization status without prompting the user.
    public func checkPermissions() {
        self.authorizationStatus = photoProvider.authorizationStatus
    }

    /// Explicitly prompts the user for photo library permissions and triggers library load on grant.
    public func requestAuthorization() async {
        isLoading = true
        errorMessage = nil

        let status = await photoProvider.requestAuthorizationStatus()
        self.authorizationStatus = status
        self.isLoading = false

        if status.canReadPhotos {
            await loadLibrary()
        } else if status == .denied {
            self.errorMessage = "Photo library access was denied. Enable permissions in Settings to organize photos."
        } else if status == .restricted {
            self.errorMessage = "Photo library access is restricted on this device by parental controls or device management."
        }
    }

    /// Triggers deep link to system settings.
    public func openSettings() async {
        await photoProvider.openSettings()
    }

    /// Presents native limited photo selection modal.
    public func presentLimitedLibraryPicker() async {
        await photoProvider.presentLimitedLibraryPicker()
    }

    // MARK: - Library Loading & Bucketing

    /// Convenience alias for `loadLibrary()`.
    public func fetchBuckets() async {
        await loadLibrary()
    }

    /// Ingests all monthly buckets and recalculates clutter summaries.
    public func loadLibrary() async {
        guard authorizationStatus.canReadPhotos else {
            logger.notice("Skipping library load: permissions not granted.")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let buckets = try await photoProvider.fetchMonthlyBuckets()
            self.monthlyBuckets = buckets

            // Pre-calculate clutter summaries across categories
            await refreshClutterSummaries()

            self.isLoading = false
            logger.info("Loaded \(buckets.count, privacy: .public) monthly buckets.")
        } catch {
            self.isLoading = false
            self.errorMessage = "Failed to load photo library: \(error.localizedDescription)"
            logger.error("Library load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Selects a specific month bucket and loads its assets for swiping.
    public func selectBucket(_ bucket: MonthlyBucket) async {
        self.selectedBucket = bucket
        self.selectedClutterCategory = nil
        self.selectedClutterClusters = []
        self.selectedClutterAssets = []

        isLoading = true
        do {
            let assets = try await photoProvider.fetchAssets(for: bucket.identifier)
            self.selectedBucketAssets = assets
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = "Failed to load assets for \(bucket.identifier.title): \(error.localizedDescription)"
        }
    }

    /// Selects a clutter category and loads its clusters and assets for swiping.
    public func selectClutterCategory(_ category: ClutterCategoryType) async {
        self.selectedClutterCategory = category
        self.selectedBucket = nil
        self.selectedBucketAssets = []

        isLoading = true
        do {
            let clusters = try await photoProvider.fetchClutterClusters(category)
            self.selectedClutterClusters = clusters
            self.selectedClutterAssets = clusters.flatMap(\.assets)
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = "Failed to load \(category.rawValue): \(error.localizedDescription)"
        }
    }

    /// Refreshes all active data following an external change notification or deletion.
    public func refresh() async {
        guard authorizationStatus.canReadPhotos else { return }

        do {
            let buckets = try await photoProvider.fetchMonthlyBuckets()
            self.monthlyBuckets = buckets

            // Refresh selected bucket if active
            if let activeBucket = selectedBucket {
                let assets = try await photoProvider.fetchAssets(for: activeBucket.identifier)
                self.selectedBucketAssets = assets
                self.selectedBucket = buckets.first(where: { $0.identifier == activeBucket.identifier })
            }

            // Refresh selected clutter if active
            if let activeCategory = selectedClutterCategory {
                let clusters = try await photoProvider.fetchClutterClusters(activeCategory)
                self.selectedClutterClusters = clusters
                self.selectedClutterAssets = clusters.flatMap(\.assets)
            }

            await refreshClutterSummaries()
        } catch {
            logger.error("Error refreshing library: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Clutter Summaries

    private func refreshClutterSummaries() async {
        var countMap: [ClutterCategoryType: Int] = [:]
        var byteMap: [ClutterCategoryType: Int64] = [:]

        for category in ClutterCategoryType.allCases {
            do {
                let clusters = try await photoProvider.fetchClutterClusters(category)
                let totalCount = clusters.reduce(0) { $0 + $1.count }
                let totalBytes = clusters.reduce(0) { $0 + $1.totalByteSize }
                countMap[category] = totalCount
                byteMap[category] = totalBytes
            } catch {
                countMap[category] = 0
                byteMap[category] = 0
            }
        }

        self.clutterSummary = countMap
        self.clutterByteSummary = byteMap
    }

    // MARK: - PhotoLibraryObserving Conformance

    public nonisolated func photoLibraryDidChange() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.logger.info("Observed external library change; refreshing view model.")
            await self.refresh()
        }
    }
}
