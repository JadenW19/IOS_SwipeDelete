//
//  SwipeAction.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation

/// Records a committed swipe gesture for LIFO undo stack restoration and historical audit.
/// Conforms to `Sendable, Equatable, Codable, Identifiable` as an immutable record of a user decision.
public struct SwipeAction: Identifiable, Sendable, Codable, Equatable {
    /// Unique identifier for this discrete action event.
    public let id: UUID

    /// Target photo library asset identifier.
    public let assetId: String

    /// Decision outcome: `.retain` (keep) or `.stageDelete` (stage for deletion).
    public let direction: SwipeDirection

    /// Timestamp when gesture decision was committed.
    public let timestamp: Date

    /// Source month or clutter category bucket identifier.
    public let bucketId: String

    /// Estimated byte size of the swiped asset.
    public let byteSize: Int64

    /// Computed alias for byte size conforming to specification naming.
    public var estimatedSizeBytes: Int64 {
        byteSize
    }

    public init(
        id: UUID = UUID(),
        assetId: String,
        direction: SwipeDirection,
        timestamp: Date = Date(),
        bucketId: String = "",
        byteSize: Int64 = 0
    ) {
        self.id = id
        self.assetId = assetId
        self.direction = direction
        self.timestamp = timestamp
        self.bucketId = bucketId
        self.byteSize = byteSize
    }
}
