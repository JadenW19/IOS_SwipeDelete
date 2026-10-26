//
//  StagedAssetItem.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation

/// Categorization of media items in the staged deletion queue.
public enum StagedMediaType: String, Sendable, Codable, CaseIterable, Equatable {
    case photo = "photo"
    case video = "video"
    case screenshot = "screenshot"
    case livePhoto = "live_photo"
}

/// An immutable item staged in the review queue awaiting deletion confirmation.
public struct StagedAssetItem: Identifiable, Sendable, Codable, Equatable, Hashable {
    public let id: String
    public let localIdentifier: String
    public let sourceBucketId: String
    public var originalBucketId: String { sourceBucketId }
    public let creationDate: Date
    public let mediaType: StagedMediaType
    public let byteSize: Int64
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let duration: TimeInterval
    public let isFavorite: Bool
    public let isScreenshot: Bool
    public let stagedTimestamp: Date
    public let photoAsset: PhotoAssetModel

    public init(
        photoAsset: PhotoAssetModel,
        stagedTimestamp: Date = Date(),
        originalBucketId: String = "active"
    ) {
        self.id = photoAsset.id
        self.localIdentifier = photoAsset.localIdentifier
        self.sourceBucketId = originalBucketId
        self.creationDate = photoAsset.creationDate

        let mappedType: StagedMediaType
        if photoAsset.mediaType == .video {
            mappedType = .video
        } else if photoAsset.isScreenshot {
            mappedType = .screenshot
        } else {
            mappedType = .photo
        }
        self.mediaType = mappedType
        self.byteSize = max(0, photoAsset.estimatedByteSize)
        self.pixelWidth = photoAsset.pixelWidth
        self.pixelHeight = photoAsset.pixelHeight
        self.duration = photoAsset.duration
        self.isFavorite = photoAsset.isFavorite
        self.isScreenshot = photoAsset.isScreenshot
        self.stagedTimestamp = stagedTimestamp
        self.photoAsset = photoAsset
    }

    public init(
        id: String,
        localIdentifier: String = "",
        sourceBucketId: String = "active",
        creationDate: Date = Date(),
        mediaType: StagedMediaType = .photo,
        byteSize: Int64 = 0,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        duration: TimeInterval = 0,
        isFavorite: Bool = false,
        isScreenshot: Bool = false,
        stagedTimestamp: Date = Date(),
        photoAsset: PhotoAssetModel? = nil
    ) {
        self.id = id
        let effectiveLocalId = localIdentifier.isEmpty ? "ph-\(id)" : localIdentifier
        self.localIdentifier = effectiveLocalId
        self.sourceBucketId = sourceBucketId
        self.creationDate = creationDate
        self.mediaType = (mediaType == .photo && isScreenshot) ? .screenshot : mediaType
        self.byteSize = max(0, byteSize)
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.isFavorite = isFavorite
        self.isScreenshot = isScreenshot || (mediaType == .screenshot)
        self.stagedTimestamp = stagedTimestamp

        if let existingAsset = photoAsset {
            self.photoAsset = existingAsset
        } else {
            let assetMediaType: AssetMediaType = (mediaType == .video) ? .video : .image
            var subtypes: AssetMediaSubtypes = []
            if isScreenshot || mediaType == .screenshot {
                subtypes.insert(.photoScreenshot)
            }
            if mediaType == .livePhoto {
                subtypes.insert(.photoLive)
            }

            self.photoAsset = PhotoAssetModel(
                id: id,
                localIdentifier: effectiveLocalId,
                creationDate: creationDate,
                mediaType: assetMediaType,
                mediaSubtypes: subtypes,
                pixelWidth: pixelWidth > 0 ? pixelWidth : 1179,
                pixelHeight: pixelHeight > 0 ? pixelHeight : 2556,
                duration: duration,
                estimatedByteSize: max(0, byteSize),
                isFavorite: isFavorite
            )
        }
    }

    public init(
        id: String,
        localIdentifier: String = "",
        sourceBucketId: String = "active",
        creationDate: Date = Date(),
        mediaType: AssetMediaType,
        byteSize: Int64 = 0,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        duration: TimeInterval = 0,
        isFavorite: Bool = false,
        isScreenshot: Bool = false,
        stagedTimestamp: Date = Date()
    ) {
        let mapped: StagedMediaType
        if mediaType == .video {
            mapped = .video
        } else if isScreenshot {
            mapped = .screenshot
        } else {
            mapped = .photo
        }
        self.init(
            id: id,
            localIdentifier: localIdentifier,
            sourceBucketId: sourceBucketId,
            creationDate: creationDate,
            mediaType: mapped,
            byteSize: byteSize,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            duration: duration,
            isFavorite: isFavorite,
            isScreenshot: isScreenshot,
            stagedTimestamp: stagedTimestamp
        )
    }
}
