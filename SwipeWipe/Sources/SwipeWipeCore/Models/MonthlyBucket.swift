//
//  MonthlyBucket.swift
//  SwipeWipeCore
//
//  Production-grade Swift 6 chronological bucketing models.
//

import Foundation

/// Value type identifying a specific calendar month and year cohort.
public struct MonthIdentifier: Hashable, Comparable, Sendable, Identifiable, Codable {
    public let year: Int
    public let month: Int // 1...12

    public var id: String {
        String(format: "%04d-%02d", year, month)
    }

    /// Full title (e.g. "October 2026").
    public var title: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let monthName = formatter.monthSymbols[max(0, min(11, month - 1))]
        return "\(monthName) \(year)"
    }

    /// Abbreviated title (e.g. "Oct 2026").
    public var shortTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let monthName = formatter.shortMonthSymbols[max(0, min(11, month - 1))]
        return "\(monthName) \(year)"
    }

    public init(year: Int, month: Int) {
        self.year = year
        self.month = max(1, min(12, month))
    }

    /// Initializes a `MonthIdentifier` extracting year and month from a given `Date` using the specified calendar.
    public init(date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) {
        let components = calendar.dateComponents([.year, .month], from: date)
        self.year = components.year ?? 1970
        self.month = components.month ?? 1
    }

    // Comparable conformance: chronological ordering
    public static func < (lhs: MonthIdentifier, rhs: MonthIdentifier) -> Bool {
        if lhs.year != rhs.year {
            return lhs.year < rhs.year
        }
        return lhs.month < rhs.month
    }
}

/// Represents an aggregated chronological month cohort containing assets and summary statistics.
public struct MonthlyBucket: Identifiable, Sendable, Hashable, Codable {
    public var id: MonthIdentifier { identifier }
    public let identifier: MonthIdentifier
    public let assetCount: Int
    public let totalByteSizeEstimate: Int64
    public let coverAssetIdentifier: String?
    public let assets: [PhotoAssetModel]

    public var formattedByteSize: String {
        guard totalByteSizeEstimate > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(totalByteSizeEstimate)
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
        identifier: MonthIdentifier,
        assetCount: Int? = nil,
        totalByteSizeEstimate: Int64? = nil,
        coverAssetIdentifier: String? = nil,
        assets: [PhotoAssetModel] = []
    ) {
        self.identifier = identifier
        self.assets = assets
        self.assetCount = assetCount ?? assets.count
        self.totalByteSizeEstimate = totalByteSizeEstimate ?? assets.reduce(0) { $0 + $1.estimatedByteSize }
        self.coverAssetIdentifier = coverAssetIdentifier ?? assets.first?.localIdentifier
    }
}
