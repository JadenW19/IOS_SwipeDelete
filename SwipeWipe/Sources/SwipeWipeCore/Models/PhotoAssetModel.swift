//
//  PhotoAssetModel.swift
//  SwipeWipeCore
//
//  Production-grade Swift 6 domain model representing an immutable photo or video asset.
//

import Foundation
import CoreGraphics

/// Categorization of media asset types conforming to PhotoKit and custom ingestion.
public enum AssetMediaType: String, Sendable, Codable, CaseIterable {
    case image
    case video
    case audio
    case unknown

    public static var photo: AssetMediaType { .image }
    public static var screenshot: AssetMediaType { .image }
}

/// Bitmask option set representing specialized asset subtypes (screenshots, HDR, bursts, high frame rate, etc.).
public struct AssetMediaSubtypes: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    // Photo Subtypes
    public static let photoPanorama    = AssetMediaSubtypes(rawValue: 1 << 0)
    public static let photoHDR         = AssetMediaSubtypes(rawValue: 1 << 1)
    public static let photoScreenshot  = AssetMediaSubtypes(rawValue: 1 << 2)
    public static let photoLive        = AssetMediaSubtypes(rawValue: 1 << 3)
    public static let photoDepthEffect = AssetMediaSubtypes(rawValue: 1 << 4)

    // Video Subtypes
    public static let videoStreamed      = AssetMediaSubtypes(rawValue: 1 << 16)
    public static let videoHighFrameRate = AssetMediaSubtypes(rawValue: 1 << 17)
    public static let videoTimelapse     = AssetMediaSubtypes(rawValue: 1 << 18)
}

/// Immutable, thread-safe domain model representing a photo or video asset in the SwipeWipe system.
public struct PhotoAssetModel: Identifiable, Hashable, Sendable, Codable {
    /// Unique identifier for UI diffing and collection views.
    public let id: String

    /// PhotoKit localIdentifier (e.g. "9F920F55-40CE-401A-B82E-C4E13F987654/L0/001").
    public let localIdentifier: String

    /// The date the asset was originally captured.
    public let creationDate: Date

    /// The date the asset was last modified, if any.
    public let modificationDate: Date?

    /// General media type (image, video, etc.).
    public let mediaType: AssetMediaType

    /// Fine-grained media subtype flags (e.g. screenshot, HDR, high frame rate).
    public let mediaSubtypes: AssetMediaSubtypes

    /// Width of the unrotated asset in pixels.
    public let pixelWidth: Int

    /// Height of the unrotated asset in pixels.
    public let pixelHeight: Int

    /// Duration in seconds (0.0 for still photos; > 0 for video assets).
    public let duration: TimeInterval

    /// Estimated or exact byte size on disk.
    public let estimatedByteSize: Int64

    /// Indicates whether the user marked this photo as a favorite in iOS Photos.
    public let isFavorite: Bool

    /// Indicates whether the asset is hidden in the user's camera roll.
    public let isHidden: Bool

    /// Identifier grouping photos captured during the same burst shutter sequence.
    public let burstIdentifier: String?

    /// True if this photo represents a burst capture group.
    public let representsBurst: Bool

    /// 64-bit perceptual difference hash (dHash) for visual similarity clustering.
    public let perceptualHash: UInt64?

    /// Computed aspect ratio (width / height), safely defaulting to 1.0 if height is zero.
    public var aspectRatio: CGFloat {
        guard pixelHeight > 0 else { return 1.0 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }

    /// User-facing human-readable file size string.
    public var formattedSize: String {
        guard estimatedByteSize > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(estimatedByteSize)
        var unitIndex = 0
        while size >= 1000.0 && unitIndex < units.count - 1 {
            size /= 1000.0
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(Int(size)) B"
        } else if size >= 100.0 {
            return String(format: "%.0f %@", size, units[unitIndex])
        } else if size >= 10.0 {
            return String(format: "%.1f %@", size, units[unitIndex])
        } else {
            return String(format: "%.2f %@", size, units[unitIndex])
        }
    }

    /// Convenience flag indicating if this asset is a screenshot.
    public var isScreenshot: Bool {
        mediaSubtypes.contains(.photoScreenshot)
    }

    /// Convenience flag indicating if this asset qualifies as a large video (duration >= 60s or size >= 100MB).
    public var isLargeVideo: Bool {
        mediaType == .video && (duration >= 60.0 || estimatedByteSize >= 100_000_000)
    }

    /// Memberwise initializer with robust defaults.
    public init(
        id: String = UUID().uuidString,
        localIdentifier: String = UUID().uuidString,
        creationDate: Date = Date(),
        modificationDate: Date? = nil,
        mediaType: AssetMediaType = .image,
        mediaSubtypes: AssetMediaSubtypes = [],
        pixelWidth: Int = 1179,
        pixelHeight: Int = 2556,
        duration: TimeInterval = 0,
        estimatedByteSize: Int64 = 3_500_000,
        isFavorite: Bool = false,
        isHidden: Bool = false,
        burstIdentifier: String? = nil,
        representsBurst: Bool = false,
        perceptualHash: UInt64? = nil
    ) {
        self.id = id
        self.localIdentifier = localIdentifier
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.mediaType = mediaType
        self.mediaSubtypes = mediaSubtypes
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.estimatedByteSize = max(0, estimatedByteSize)
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.burstIdentifier = burstIdentifier
        self.representsBurst = representsBurst
        self.perceptualHash = perceptualHash
    }
}
