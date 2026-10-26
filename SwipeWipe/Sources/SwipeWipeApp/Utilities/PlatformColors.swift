//
//  PlatformColors.swift
//  SwipeWipeApp
//
//  Cross-platform color and view compatibility layer for iOS and macOS.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if !canImport(UIKit)
/// Compatibility token for macOS builds allowing iOS system background colors to resolve cleanly.
public struct AppColorToken: Sendable, Equatable {
    public let rawValue: String

    public static let systemBackground = AppColorToken(rawValue: "systemBackground")
    public static let secondarySystemBackground = AppColorToken(rawValue: "secondarySystemBackground")
    public static let tertiarySystemBackground = AppColorToken(rawValue: "tertiarySystemBackground")
}

public typealias UIColor = AppColorToken

extension Color {
    public init(_ token: AppColorToken) {
        #if canImport(AppKit)
        switch token {
        case .secondarySystemBackground:
            self = Color(NSColor.controlBackgroundColor)
        case .tertiarySystemBackground:
            self = Color(NSColor.underPageBackgroundColor)
        default:
            self = Color(NSColor.windowBackgroundColor)
        }
        #else
        switch token {
        case .secondarySystemBackground:
            self = Color(white: 0.5, opacity: 0.15)
        case .tertiarySystemBackground:
            self = Color(white: 0.5, opacity: 0.10)
        default:
            self = Color(white: 1.0)
        }
        #endif
    }
}
#endif
