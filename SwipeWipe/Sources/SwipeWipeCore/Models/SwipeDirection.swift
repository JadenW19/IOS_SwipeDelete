//
//  SwipeDirection.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation

/// Primary decision outcome for a card gesture.
public enum SwipeDirection: String, CaseIterable, Sendable, Codable, Equatable {
    /// Swipe right: Retain asset in photo library (Keep).
    case retain = "retain"
    /// Swipe left: Stage asset for batch deletion review (Trash).
    case stageDelete = "stage_delete"
    /// Swipe up: Skip asset or inspect details without committing decision.
    case skip = "skip"
}
