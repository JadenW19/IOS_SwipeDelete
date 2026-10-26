//
//  MockHapticFeedbackService.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation

/// Test spy implementation of `HapticFeedbackServiceProtocol` recording feedback events.
public final class MockHapticFeedbackService: HapticFeedbackServiceProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var thresholdFired: Bool = false

    public private(set) var recordedEvents: [String] = []

    public init() {}

    public func triggerImpact(style: HapticFeedbackStyle) {
        lock.lock()
        defer { lock.unlock() }
        recordedEvents.append("IMPACT_\(style)")
    }

    public func triggerNotification(type: HapticNotificationType) {
        lock.lock()
        defer { lock.unlock() }
        switch type {
        case .success:
            recordedEvents.append("SUCCESS")
        case .warning:
            recordedEvents.append("WARNING")
        case .error:
            recordedEvents.append("ERROR")
        }
    }

    public func triggerSelection() {
        lock.lock()
        defer { lock.unlock() }
        recordedEvents.append("SELECTION")
    }

    public func updateThreshold(dx: Double, threshold: Double) {
        lock.lock()
        defer { lock.unlock() }

        let isBeyond = abs(dx) >= threshold
        if isBeyond && !thresholdFired {
            thresholdFired = true
            recordedEvents.append("THRESHOLD_CROSSED")
        } else if !isBeyond && thresholdFired {
            thresholdFired = false
        }
    }

    public func triggerCommit(direction: SwipeDirection) {
        lock.lock()
        defer { lock.unlock() }
        switch direction {
        case .retain:
            recordedEvents.append("COMMIT_RETAIN")
        case .stageDelete:
            recordedEvents.append("COMMIT_STAGE_DELETE")
        case .skip:
            recordedEvents.append("COMMIT_SKIP")
        }
    }

    public func triggerUndo() {
        lock.lock()
        defer { lock.unlock() }
        recordedEvents.append("UNDO")
    }

    public func triggerSuccess() {
        lock.lock()
        defer { lock.unlock() }
        recordedEvents.append("SUCCESS")
    }

    public func triggerWarning() {
        lock.lock()
        defer { lock.unlock() }
        recordedEvents.append("WARNING")
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        recordedEvents.removeAll()
        thresholdFired = false
    }
}
