//
//  HapticFeedbackServiceProtocol.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation

/// Supported tactile styles for Taptic Engine impacts.
public enum HapticFeedbackStyle: String, Sendable, CaseIterable {
    case light
    case medium
    case heavy
    case rigid
    case soft
}

/// Supported notification haptic types.
public enum HapticNotificationType: String, Sendable, CaseIterable {
    case success
    case warning
    case error
}

/// Abstraction for device tactile feedback, enabling hardware haptics in production
/// and event recording in automated headless test runners.
public protocol HapticFeedbackServiceProtocol: AnyObject, Sendable {
    /// Pre-warms tactile feedback generators to eliminate touch-to-impulse latency.
    func prepare()

    /// Triggers an impact feedback event with the specified style.
    func impact(style: HapticFeedbackStyle)

    /// Triggers a notification feedback event (success, warning, error).
    func notification(type: HapticNotificationType)

    /// Triggers selection feedback for subtle discrete ticks.
    func selection()

    /// Evaluates drag offset and triggers a debounced impact when crossing the decision threshold.
    func updateThreshold(dx: Double, threshold: Double)

    /// Triggers decision commit feedback in the given swipe direction.
    func triggerCommit(direction: SwipeDirection)

    /// Triggers tactile pop when restoring an undone card to index 0.
    func triggerUndo()

    /// Triggers celebration notification when deck reaches the empty state.
    func triggerSuccess()

    /// Triggers alert haptic when staging a favorited asset or attempting an invalid action.
    func triggerWarning()

    // MARK: - Compatibility & Trigger Methods

    /// Legacy / alternate trigger method for impact feedback.
    func triggerImpact(style: HapticFeedbackStyle)

    /// Legacy / alternate trigger method for notification feedback.
    func triggerNotification(type: HapticNotificationType)

    /// Legacy / alternate trigger method for selection ticks.
    func triggerSelection()
}

// MARK: - Default Protocol Implementations

extension HapticFeedbackServiceProtocol {
    public func prepare() {}

    public func impact(style: HapticFeedbackStyle) {
        triggerImpact(style: style)
    }

    public func notification(type: HapticNotificationType) {
        triggerNotification(type: type)
    }

    public func selection() {
        triggerSelection()
    }

    public func triggerImpact(style: HapticFeedbackStyle) {
        impact(style: style)
    }

    public func triggerNotification(type: HapticNotificationType) {
        notification(type: type)
    }

    public func triggerSelection() {
        selection()
    }
}

// MARK: - Testable Mock Inspection Helpers

extension MockHapticFeedbackService {
    /// Total count of all recorded tactile events.
    public var totalEventCount: Int {
        recordedEvents.count
    }

    /// Count of specific events in the recorded log.
    public func count(of event: String) -> Int {
        recordedEvents.filter { $0 == event }.count
    }

    /// Count of impact triggers matching the specified style.
    public func impactCount(for style: HapticFeedbackStyle) -> Int {
        count(of: "IMPACT_\(style)")
    }

    /// Count of notification triggers matching the specified type.
    public func notificationCount(for type: HapticNotificationType) -> Int {
        switch type {
        case .success: return count(of: "SUCCESS")
        case .warning: return count(of: "WARNING")
        case .error: return count(of: "ERROR")
        }
    }

    /// Verifies if a specific event string was logged by the spy.
    public func contains(event: String) -> Bool {
        recordedEvents.contains(event)
    }
}
