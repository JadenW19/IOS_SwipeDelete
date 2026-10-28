//
//  PhotoLibraryService.swift
//  SwipeWipeCore
//
//  Production-grade PhotoKit bridge service with lazy querying, change observation,
//  privacy fallback handling, and user-cancellation safety guards.
//

import Foundation
import CoreGraphics
import os

#if canImport(Photos)
import Photos
#endif

#if canImport(PhotosUI)
import PhotosUI
#endif

#if canImport(UIKit)
import UIKit
#endif

/// Production implementation of `PhotoLibraryProviding` communicating directly with Apple's PhotoKit.
public final class PhotoLibraryService: NSObject, PhotoLibraryProviding, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.swipewipe.SwipeWipeCore", category: "PhotoLibraryService")
    private let clutterDetector = ClutterDetector()
    private let lock = NSLock()

    private var observers: [WeakPhotoLibraryObserver] = []

    public override init() {
        super.init()
        #if canImport(Photos)
        PHPhotoLibrary.shared().register(self)
        #endif
    }

    deinit {
        #if canImport(Photos)
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        #endif
    }

    // MARK: - Authorization Lifecycle

    public var authorizationStatus: PhotoAuthorizationStatus {
        #if canImport(Photos)
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return mapAuthorizationStatus(status)
        #else
        return .authorized
        #endif
    }

    public func requestAuthorizationStatus() async -> PhotoAuthorizationStatus {
        #if canImport(Photos)
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        let mapped = mapAuthorizationStatus(status)
        logger.info("PhotoLibrary authorization status updated to: \(mapped.rawValue, privacy: .public)")
        return mapped
        #else
        return .authorized
        #endif
    }

    public func openSettings() async {
        #if canImport(UIKit)
        await MainActor.run {
            guard let settingsURL = URL(string: UIApplication.openSettingsURLString),
                  UIApplication.shared.canOpenURL(settingsURL) else {
                return
            }
            UIApplication.shared.open(settingsURL)
        }
        #endif
    }

    public func presentLimitedLibraryPicker() async {
        #if canImport(Photos) && canImport(PhotosUI) && canImport(UIKit)
        await MainActor.run {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else {
                return
            }
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootVC)
        }
        #endif
    }

    // MARK: - Asset Ingestion & Bucketing

    public func fetchMonthlyBuckets() async throws -> [MonthlyBucket] {
        guard authorizationStatus.canReadPhotos else {
            logger.warning("Attempted to fetch monthly buckets without read permissions.")
            return []
        }

        #if canImport(Photos)
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        var bucketMap: [MonthIdentifier: [PhotoAssetModel]] = [:]

        fetchResult.enumerateObjects { asset, _, _ in
            let model = Self.convertPHAsset(asset)
            let monthId = MonthIdentifier(date: model.creationDate)
            bucketMap[monthId, default: []].append(model)
        }

        let buckets = bucketMap.keys.sorted(by: >).map { monthId in
            let assets = bucketMap[monthId] ?? []
            return MonthlyBucket(
                identifier: monthId,
                assetCount: assets.count,
                totalByteSizeEstimate: assets.reduce(0) { $0 + $1.estimatedByteSize },
                coverAssetIdentifier: assets.first?.localIdentifier,
                assets: assets
            )
        }

        logger.info("Successfully fetched \(buckets.count, privacy: .public) monthly buckets.")
        return buckets
        #else
        return []
        #endif
    }

    public func fetchAssets(for bucketId: MonthIdentifier) async throws -> [PhotoAssetModel] {
        guard authorizationStatus.canReadPhotos else { return [] }

        #if canImport(Photos)
        let calendar = Calendar(identifier: .gregorian)
        var startComponents = DateComponents()
        startComponents.year = bucketId.year
        startComponents.month = bucketId.month
        startComponents.day = 1

        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(byAdding: .month, value: 1, to: startDate) else {
            return []
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", startDate as NSDate, endDate as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        var models: [PhotoAssetModel] = []
        models.reserveCapacity(fetchResult.count)

        fetchResult.enumerateObjects { asset, _, _ in
            models.append(Self.convertPHAsset(asset))
        }

        return models
        #else
        return []
        #endif
    }

    // MARK: - Clutter Categorization

    public func fetchClutterClusters(_ category: ClutterCategoryType) async throws -> [ClutterCluster] {
        guard authorizationStatus.canReadPhotos else { return [] }

        #if canImport(Photos)
        switch category {
        case .screenshots:
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: options)
            var models: [PhotoAssetModel] = []
            result.enumerateObjects { asset, _, _ in
                models.append(Self.convertPHAsset(asset))
            }
            return clutterDetector.detectScreenshots(in: models)

        case .largeVideos:
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "duration", ascending: false)]
            let result = PHAsset.fetchAssets(with: options)
            var models: [PhotoAssetModel] = []
            result.enumerateObjects { asset, _, _ in
                models.append(Self.convertPHAsset(asset))
            }
            return clutterDetector.detectLargeVideos(in: models)

        case .bursts:
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "burstIdentifier != nil")
            let result = PHAsset.fetchAssets(with: options)
            var models: [PhotoAssetModel] = []
            result.enumerateObjects { asset, _, _ in
                models.append(Self.convertPHAsset(asset))
            }
            return clutterDetector.detectBurstGroups(in: models)

        case .duplicates:
            // Fetch recent 3,000 photos for duplicate temporal scanning
            let options = PHFetchOptions()
            options.fetchLimit = 3000
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: .image, options: options)
            var models: [PhotoAssetModel] = []
            result.enumerateObjects { asset, _, _ in
                models.append(Self.convertPHAsset(asset))
            }
            return clutterDetector.detectDuplicates(in: models)
        }
        #else
        return []
        #endif
    }

    // MARK: - Batch Deletion

    @discardableResult
    public func deleteAssets(withIdentifiers ids: [String]) async throws -> BatchDeletionResult {
        guard !ids.isEmpty else {
            return BatchDeletionResult(success: true, deletedCount: 0, reclaimedBytes: 0)
        }

        #if canImport(Photos)
        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                PHAssetChangeRequest.deleteAssets(assets)
            }) { success, error in
                if success {
                    self.logger.info("Successfully deleted \(ids.count, privacy: .public) assets from PhotoKit.")
                    continuation.resume(returning: BatchDeletionResult(
                        success: true,
                        deletedCount: ids.count,
                        reclaimedBytes: 0,
                        failedIdentifiers: []
                    ))
                } else if let nsError = error as NSError? {
                    // Check for user cancellation error code 3072 (PHPhotosError.userCancelled)
                    if nsError.domain == "PHPhotosErrorDomain" && nsError.code == 3072 {
                        self.logger.notice("User cancelled native PhotoKit deletion modal (Error code 3072).")
                        continuation.resume(throwing: nsError)
                    } else {
                        self.logger.error("PhotoKit batch deletion failed: \(nsError.localizedDescription, privacy: .public)")
                        continuation.resume(throwing: nsError)
                    }
                } else {
                    let unknownError = NSError(
                        domain: "com.swipewipe.PhotoLibraryService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Unknown deletion error occurred"]
                    )
                    continuation.resume(throwing: unknownError)
                }
            }
        }
        #else
        return BatchDeletionResult(success: true, deletedCount: ids.count, reclaimedBytes: 0)
        #endif
    }

    // MARK: - Thumbnail Loading

    private final class ThumbnailContinuationGuard: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false

        func resumeOnce(_ continuation: CheckedContinuation<CGImage?, Never>, returning image: CGImage?) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            continuation.resume(returning: image)
        }
    }

    public func loadThumbnail(for assetId: String, targetSize: CGSize) async throws -> CGImage? {
        #if canImport(Photos)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let phAsset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false

        let continuationGuard = ThumbnailContinuationGuard()
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: phAsset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
                let hasError = info?[PHImageErrorKey] != nil
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? (info?[PHImageCancelledKey] as? NSNumber)?.boolValue ?? false

                // If degraded preview is delivered and request is actively pending, wait for final pass
                if isDegraded && !hasError && !isCancelled {
                    return
                }

                #if canImport(UIKit)
                continuationGuard.resumeOnce(continuation, returning: image?.cgImage)
                #else
                continuationGuard.resumeOnce(continuation, returning: nil)
                #endif
            }
        }
        #else
        return nil
        #endif
    }

    // MARK: - Observers

    public func addObserver(_ observer: PhotoLibraryObserving) {
        lock.lock()
        defer { lock.unlock() }
        observers.removeAll { $0.value == nil || $0.value === observer }
        observers.append(WeakPhotoLibraryObserver(observer))
    }

    public func removeObserver(_ observer: PhotoLibraryObserving) {
        lock.lock()
        defer { lock.unlock() }
        observers.removeAll { $0.value == nil || $0.value === observer }
    }

    // MARK: - Private Helpers

    #if canImport(Photos)
    private func mapAuthorizationStatus(_ status: PHAuthorizationStatus) -> PhotoAuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .authorized:    return .authorized
        case .limited:       return .limited
        @unknown default:    return .notDetermined
        }
    }

    private static func convertPHAsset(_ asset: PHAsset) -> PhotoAssetModel {
        var mediaType: AssetMediaType = .unknown
        switch asset.mediaType {
        case .image: mediaType = .image
        case .video: mediaType = .video
        case .audio: mediaType = .audio
        case .unknown: mediaType = .unknown
        @unknown default: mediaType = .unknown
        }

        var subtypes: AssetMediaSubtypes = []
        if asset.mediaSubtypes.contains(.photoPanorama) { subtypes.insert(.photoPanorama) }
        if asset.mediaSubtypes.contains(.photoHDR) { subtypes.insert(.photoHDR) }
        if asset.mediaSubtypes.contains(.photoScreenshot) { subtypes.insert(.photoScreenshot) }
        if asset.mediaSubtypes.contains(.photoLive) { subtypes.insert(.photoLive) }
        if asset.mediaSubtypes.contains(.photoDepthEffect) { subtypes.insert(.photoDepthEffect) }
        if asset.mediaSubtypes.contains(.videoStreamed) { subtypes.insert(.videoStreamed) }
        if asset.mediaSubtypes.contains(.videoHighFrameRate) { subtypes.insert(.videoHighFrameRate) }
        if asset.mediaSubtypes.contains(.videoTimelapse) { subtypes.insert(.videoTimelapse) }

        // Estimate byte size based on asset dimensions and type
        let estimatedSize: Int64
        if mediaType == .video {
            let durationSeconds = asset.duration
            estimatedSize = max(5_000_000, Int64(durationSeconds * 2_500_000))
        } else if subtypes.contains(.photoScreenshot) {
            estimatedSize = 1_800_000
        } else {
            let pixels = asset.pixelWidth * asset.pixelHeight
            estimatedSize = max(2_000_000, Int64(Double(pixels) * 0.45))
        }

        return PhotoAssetModel(
            id: asset.localIdentifier,
            localIdentifier: asset.localIdentifier,
            creationDate: asset.creationDate ?? asset.modificationDate ?? Date(timeIntervalSince1970: 0),
            modificationDate: asset.modificationDate,
            mediaType: mediaType,
            mediaSubtypes: subtypes,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration,
            estimatedByteSize: estimatedSize,
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            burstIdentifier: asset.burstIdentifier,
            representsBurst: asset.representsBurst
        )
    }
    #endif
}

// MARK: - PHPhotoLibraryChangeObserver Conformance

#if canImport(Photos)
extension PhotoLibraryService: PHPhotoLibraryChangeObserver {
    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        lock.lock()
        observers.removeAll { $0.value == nil }
        let currentObservers = observers.compactMap(\.value)
        lock.unlock()

        logger.debug("Received PhotoKit external change notification. Notifying \(currentObservers.count) observers.")
        for observer in currentObservers {
            observer.photoLibraryDidChange()
        }
    }
}
#endif
