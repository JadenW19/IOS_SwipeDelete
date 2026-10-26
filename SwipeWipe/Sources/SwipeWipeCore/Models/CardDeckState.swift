//
//  CardDeckState.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation

/// State machine governing the swiping card deck visual presentation and gesture handling.
public enum CardDeckState: String, Sendable, Codable, Equatable {
    /// Idle state waiting for user interaction.
    case idle
    /// Active drag gesture in progress.
    case dragging
    /// Card is flying offscreen with spring animation.
    case animatingDismissal
    /// Gesture released below threshold, springing back to center.
    case animatingRebound
    /// All cards in current cohort or bucket have been processed.
    case empty
}
