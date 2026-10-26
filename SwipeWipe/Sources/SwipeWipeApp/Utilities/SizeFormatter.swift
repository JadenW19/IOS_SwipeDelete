//
//  SizeFormatter.swift
//  SwipeWipeApp
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation
import SwipeWipeCore

/// Presentation-layer size formatting utilities for SwipeWipeApp views,
/// implementing standard Apple Human Interface Guidelines decimal byte counts (1,000 = 1 KB).
public enum AppSizeFormatter: Sendable {

    /// Formats a byte count into a localized human-readable string using Apple ByteCountFormatter.
    public static func format(bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let bcf = ByteCountFormatter()
        bcf.countStyle = .file
        bcf.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        bcf.includesUnit = true
        bcf.isAdaptive = true
        return bcf.string(fromByteCount: bytes)
    }

    /// Pure Swift deterministic decimal byte count formatter (1,000 B = 1 KB, 1,000 KB = 1 MB, etc.).
    public static func formatDeterministic(bytes: Int64) -> String {
        SwipeWipeCore.SizeFormatter.formatDeterministic(bytes: bytes)
    }
}
