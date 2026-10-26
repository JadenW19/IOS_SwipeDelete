//
//  HapticFeedbackService.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Production implementation of `HapticFeedbackServiceProtocol` driving the Apple Taptic Engine.
/// Incorporates debouncing logic (`hasCrossedThreshold`) to prevent sensory fatigue during 120Hz ProMotion gestures.
public final class HapticFeedbackService: HapticFeedbackServiceProtocol, @unchecked Sendable {

    private let lock = NSLock()

    /// Debouncing flag indicating if the drag gesture has crossed the decision threshold.
    public private(set) var hasCrossedThreshold: Bool = false

    #if canImport(UIKit)
    private var lightImpactGenerator: UIImpactFeedbackGenerator?
    private var mediumImpactGenerator: UIImpactFeedbackGenerator?
    private var heavyImpactGenerator: UIImpactFeedbackGenerator?
    private var rigidImpactGenerator: UIImpactFeedbackGenerator?
    private var softImpactGenerator: UIImpactFeedbackGenerator?
    private var notificationGenerator: UINotificationFeedbackGenerator?
    private var selectionGenerator: UISelectionFeedbackGenerator?
    #endif

    public init() {
        #if canImport(UIKit)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
            self.mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
            self.heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
            self.rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)
            self.softImpactGenerator = UIImpactFeedbackGenerator(style: .soft)
            self.notificationGenerator = UINotificationFeedbackGenerator()
            self.selectionGenerator = UISelectionFeedbackGenerator()
            self.prepare()
        }
        #endif
    }

    /// Pre-warms the Taptic Engine generators to guarantee sub-millisecond tactile response.
    public func prepare() {
        #if canImport(UIKit)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lightImpactGenerator?.prepare()
            self.mediumImpactGenerator?.prepare()
            self.heavyImpactGenerator?.prepare()
            self.rigidImpactGenerator?.prepare()
            self.softImpactGenerator?.prepare()
            self.notificationGenerator?.prepare()
            self.selectionGenerator?.prepare()
        }
        #endif
    }

    /// Triggers physical impact feedback according to specified style.
    public func impact(style: HapticFeedbackStyle) {
        #if canImport(UIKit)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch style {
            case .light:
                self.lightImpactGenerator?.impactOccurred()
                self.lightImpactGenerator?.prepare()
            case .medium:
                self.mediumImpactGenerator?.impactOccurred()
                self.mediumImpactGenerator?.prepare()
            case .heavy:
                self.heavyImpactGenerator?.impactOccurred()
                self.heavyImpactGenerator?.prepare()
            case .rigid:
                self.rigidImpactGenerator?.impactOccurred()
                self.rigidImpactGenerator?.prepare()
            case .soft:
                self.softImpactGenerator?.impactOccurred()
                self.softImpactGenerator?.prepare()
            }
        }
        #endif
    }

    /// Triggers system notification feedback (success, warning, error).
    public func notification(type: HapticNotificationType) {
        #if canImport(UIKit)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch type {
            case .success:
                self.notificationGenerator?.notificationOccurred(.success)
            case .warning:
                self.notificationGenerator?.notificationOccurred(.warning)
            case .error:
                self.notificationGenerator?.notificationOccurred(.error)
            }
            self.notificationGenerator?.prepare()
        }
        #endif
    }

    /// Triggers discrete selection tick.
    public func selection() {
        #if canImport(UIKit)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.selectionGenerator?.selectionChanged()
            self.selectionGenerator?.prepare()
        }
        #endif
    }

    /// Evaluates drag offset against decision threshold with debouncing to prevent sensory fatigue during 120Hz gesture tracking.
    public func updateThreshold(dx: Double, threshold: Double = 137.5) {
        lock.lock()
        defer { lock.unlock() }

        let isBeyond = abs(dx) >= threshold
        if isBeyond && !hasCrossedThreshold {
            hasCrossedThreshold = true
            impact(style: .medium)
        } else if !isBeyond && hasCrossedThreshold {
            hasCrossedThreshold = false
        }
    }

    /// Dispatches committed swipe direction tactile confirmation.
    public func triggerCommit(direction: SwipeDirection) {
        switch direction {
        case .retain:
            impact(style: .light)
        case .stageDelete:
            impact(style: .medium)
        case .skip:
            selection()
        }
    }

    /// Dispatches undo restoration tactile feedback.
    public func triggerUndo() {
        impact(style: .soft)
    }

    /// Dispatches completion celebration tactile notification.
    public func triggerSuccess() {
        notification(type: .success)
    }

    /// Dispatches warning tactile alert.
    public func triggerWarning() {
        notification(type: .warning)
    }

    /// Manually resets threshold crossing state.
    public func resetThreshold() {
        lock.lock()
        defer { lock.unlock() }
        hasCrossedThreshold = false
    }
}
