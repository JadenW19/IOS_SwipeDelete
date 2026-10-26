//
//  ClutterCategory.swift
//  SwipeWipeCore
//
//  Production-grade Swift 6 clutter categories and clusters.
//

import Foundation

/// Defines high-impact clutter categories identified in the camera roll.
public enum ClutterCategoryType: String, CaseIterable, Identifiable, Sendable, Codable {
    case screenshots = "Screenshots"
    case duplicates = "Duplicates"
    case largeVideos = "Large Videos"
    case bursts = "Burst Shots"

    public var id: String { rawValue }

    /// SF Symbol icon name appropriate for SwiftUI rendering.
    public var systemIcon: String {
        switch self {
        case .screenshots:
            return "camera.viewfinder"
        case .duplicates:
            return "doc.on.doc"
        case .largeVideos:
            return "video.badge.waveform"
        case .bursts:
            return "square.stack.3d.down.right"
        }
    }

    /// Descriptive summary of the category.
    public var categoryDescription: String {
        switch self {
        case .screenshots:
            return "Screen captures and device screenshots taking up unnecessary space."
        case .duplicates:
            return "Visually identical or near-identical photos taken within moments of each other."
        case .largeVideos:
            return "Videos exceeding 60 seconds or 100 MB that consume significant storage."
        case .bursts:
            return "Rapid-fire shutter sequences where only the best shot needs to be kept."
        }
    }
}

/// A cluster of related clutter assets (e.g. a group of duplicates, a burst series, or a single large item).
public struct ClutterCluster: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let category: ClutterCategoryType
    public let title: String
    public let assets: [PhotoAssetModel]
    public let totalByteSize: Int64

    /// Recommended asset to retain (e.g. user favorite, highest sharpness, or anchor shot).
    public let primaryAssetId: String?

    /// Assets recommended to stage for deletion.
    public var duplicateAssetIds: [String] {
        guard category == .duplicates || category == .bursts else {
            return []
        }
        guard let primary = primaryAssetId else {
            return assets.dropFirst().map(\.localIdentifier)
        }
        return assets.filter { $0.localIdentifier != primary }.map(\.localIdentifier)
    }

    public var count: Int {
        assets.count
    }

    public var formattedByteSize: String {
        guard totalByteSize > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(totalByteSize)
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

    public init(
        id: String = UUID().uuidString,
        category: ClutterCategoryType,
        title: String,
        assets: [PhotoAssetModel],
        totalByteSize: Int64? = nil,
        primaryAssetId: String? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.assets = assets
        self.totalByteSize = totalByteSize ?? assets.reduce(0) { $0 + $1.estimatedByteSize }
        self.primaryAssetId = primaryAssetId
    }
}

/// Aggregate model representing an entire clutter category and all its clusters.
public struct ClutterCategory: Identifiable, Sendable, Hashable, Codable {
    public var id: String { categoryType.rawValue }
    public let categoryType: ClutterCategoryType
    public let clusters: [ClutterCluster]

    public var allAssets: [PhotoAssetModel] {
        clusters.flatMap(\.assets)
    }

    public var totalAssets: Int {
        allAssets.count
    }

    public var totalByteSize: Int64 {
        clusters.reduce(0) { $0 + $1.totalByteSize }
    }

    public var formattedByteSize: String {
        guard totalByteSize > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(totalByteSize)
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

    public init(categoryType: ClutterCategoryType, clusters: [ClutterCluster] = []) {
        self.categoryType = categoryType
        self.clusters = clusters
    }
}
