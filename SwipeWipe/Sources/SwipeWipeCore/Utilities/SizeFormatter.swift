//
//  SizeFormatter.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation

/// Deterministic, locale-independent byte size formatter.
public enum SizeFormatter: Sendable {

    /// Formats a byte count into a human-readable string using decimal (SI) prefixes (1,000 = 1 KB).
    /// Follows Apple HIG for storage display with exact decimal thresholds.
    public static func formatDeterministic(bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }

        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unitIndex = 0

        while size >= 1000.0 && unitIndex < units.count - 1 {
            size /= 1000.0
            unitIndex += 1
        }

        let unit = units[unitIndex]
        if unitIndex == 0 {
            return "\(Int(size)) B"
        }

        switch unit {
        case "KB":
            if size >= 100.0 {
                return String(format: "%.0f KB", size)
            } else {
                return String(format: "%.1f KB", size)
            }
        case "MB":
            if size >= 100.0 {
                return String(format: "%.0f MB", size)
            } else {
                return String(format: "%.1f MB", size)
            }
        case "GB", "TB":
            if size >= 10.0 {
                return String(format: "%.1f %@", size, unit)
            } else {
                return String(format: "%.2f %@", size, unit)
            }
        default:
            return String(format: "%.1f %@", size, unit)
        }
    }
}
