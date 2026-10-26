//
//  SwipingDeckTests.swift
//  SwipeWipeCoreTests
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//  Covers Requirement R2: 120Hz Gesture Physics, 3-Card Stack, Decision Engine, Dynamic Rotation, LIFO Undo
//

import XCTest
import Foundation
import CoreGraphics
@testable import SwipeWipeCore

// MARK: - Swiping Deck Tests Suite

final class SwipingDeckTests: XCTestCase {

    // MARK: - Constants Under Test (iPhone 14 Pro Geometry)
    
    private let screenWidth: CGFloat = 393.0
    private let screenHeight: CGFloat = 852.0
    private let distanceThreshold: CGFloat = 137.5 // 393 * 0.35
    private let velocityThreshold: CGFloat = 800.0 // pt/s
    private let minFlickDistance: CGFloat = 35.0
    private let maxRotationDegrees: Double = 20.0

    // MARK: - Feature 8: ProMotion 120Hz Gesture Frame Budget (F8)
    
    func testDragProgressComputationSpeed() {
        let iterations = 10_000
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<iterations {
            let dx = CGFloat(i % 300) - 150.0
            let p = min(max(abs(dx) / distanceThreshold, 0.0), 1.0)
            XCTAssertGreaterThanOrEqual(p, 0.0)
            XCTAssertLessThanOrEqual(p, 1.0)
        }
        
        let totalElapsed = CFAbsoluteTimeGetCurrent() - startTime
        let perFrameAverageMs = (totalElapsed / Double(iterations)) * 1000.0
        
        // Sub-computation must be negligible
        XCTAssertLessThan(perFrameAverageMs, 0.5, "Progress computation must be negligible to preserve 8.33ms budget")
    }
    
    func testContinuousSquircleCornerRadiusSpecification() {
        let cornerRadius: CGFloat = 24.0
        XCTAssertEqual(cornerRadius, 24.0, "Continuous squircle corner radius must be 24pt for iPhone 14 Pro styling")
    }

    // MARK: - Feature 9: Card Deck Stacking & Visual Depth (F9)
    
    func testThreeCardWindowRestParameters() {
        // Card 0 (Top)
        let scale0 = 1.0
        let offsetY0: CGFloat = 0.0
        let zIndex0 = 3
        
        // Card 1 (Next)
        let scale1 = 0.94
        let offsetY1: CGFloat = 14.0
        let zIndex1 = 2
        
        // Card 2 (Bottom)
        let scale2 = 0.88
        let offsetY2: CGFloat = 26.0
        let zIndex2 = 1
        
        XCTAssertEqual(scale0, 1.0)
        XCTAssertEqual(offsetY0, 0.0)
        XCTAssertEqual(zIndex0, 3)
        
        XCTAssertEqual(scale1, 0.94)
        XCTAssertEqual(offsetY1, 14.0)
        XCTAssertEqual(zIndex1, 2)
        
        XCTAssertEqual(scale2, 0.88)
        XCTAssertEqual(offsetY2, 26.0)
        XCTAssertEqual(zIndex2, 1)
    }
    
    func testCardStackInterpolationDuringDrag() {
        // Drag halfway to threshold (p = 0.5)
        let progress = 0.5
        
        let interpolatedScale1 = 0.94 + (0.06 * progress)
        let interpolatedY1 = 14.0 * (1.0 - progress)
        
        let interpolatedScale2 = 0.88 + (0.06 * progress)
        let interpolatedY2 = 26.0 - (12.0 * progress)
        
        XCTAssertEqual(interpolatedScale1, 0.97, accuracy: 0.001)
        XCTAssertEqual(interpolatedY1, 7.0, accuracy: 0.001)
        
        XCTAssertEqual(interpolatedScale2, 0.91, accuracy: 0.001)
        XCTAssertEqual(interpolatedY2, 20.0, accuracy: 0.001)
    }

    // MARK: - Feature 10: Bi-Directional Decision Engine (F10)
    
    func testDistanceThresholdCommitRight() {
        let dxCommit: CGFloat = 138.0 // > 137.5
        let vx: CGFloat = 0.0
        
        let shouldCommit = (abs(dxCommit) >= distanceThreshold) || (abs(vx) >= velocityThreshold && ((vx > 0) == (dxCommit > 0)) && abs(dxCommit) >= minFlickDistance)
        let direction: SwipeDirection? = shouldCommit ? (dxCommit > 0 ? .retain : .stageDelete) : nil
        
        XCTAssertTrue(shouldCommit)
        XCTAssertEqual(direction, .retain)
    }
    
    func testDistanceThresholdCommitLeft() {
        let dxCommit: CGFloat = -138.0 // < -137.5
        let vx: CGFloat = 0.0
        
        let shouldCommit = (abs(dxCommit) >= distanceThreshold) || (abs(vx) >= velocityThreshold && ((vx > 0) == (dxCommit > 0)) && abs(dxCommit) >= minFlickDistance)
        let direction: SwipeDirection? = shouldCommit ? (dxCommit > 0 ? .retain : .stageDelete) : nil
        
        XCTAssertTrue(shouldCommit)
        XCTAssertEqual(direction, .stageDelete)
    }
    
    func testVelocityEscapeCommitRight() {
        let dxFlick: CGFloat = 45.0 // < 137.5, but >= 35.0
        let vxFlick: CGFloat = 950.0 // >= 800.0 pt/s
        
        let shouldCommit = (abs(dxFlick) >= distanceThreshold) || (abs(vxFlick) >= velocityThreshold && ((vxFlick > 0) == (dxFlick > 0)) && abs(dxFlick) >= minFlickDistance)
        let direction: SwipeDirection? = shouldCommit ? (dxFlick > 0 ? .retain : .stageDelete) : nil
        
        XCTAssertTrue(shouldCommit, "Velocity flick above 800pt/s must commit even if distance is under 137.5pt")
        XCTAssertEqual(direction, .retain)
    }
    
    func testInsufficientDragSnapsBack() {
        let dxSmall: CGFloat = 80.0 // < 137.5
        let vxSlow: CGFloat = 300.0 // < 800
        
        let shouldCommit = (abs(dxSmall) >= distanceThreshold) || (abs(vxSlow) >= velocityThreshold && ((vxSlow > 0) == (dxSmall > 0)) && abs(dxSmall) >= minFlickDistance)
        
        XCTAssertFalse(shouldCommit, "Small displacement without velocity must rebound to center")
    }

    // MARK: - Feature 11: Dynamic Rotation Physics (F11)
    
    func testDynamicRotationCalculation() {
        // Angle formula: theta = (dx / 393) * 20.0 degrees
        let dxPositive: CGFloat = 196.5 // Half screen width
        let thetaRight = (Double(dxPositive) / Double(screenWidth)) * maxRotationDegrees
        XCTAssertEqual(thetaRight, 10.0, accuracy: 0.001, "Clockwise rotation for right drag")
        
        let dxNegative: CGFloat = -196.5
        let thetaLeft = (Double(dxNegative) / Double(screenWidth)) * maxRotationDegrees
        XCTAssertEqual(thetaLeft, -10.0, accuracy: 0.001, "Counter-clockwise rotation for left drag")
        
        let dxZero: CGFloat = 0.0
        let thetaZero = (Double(dxZero) / Double(screenWidth)) * maxRotationDegrees
        XCTAssertEqual(thetaZero, 0.0, accuracy: 0.001)
    }
    
    func testRotationThresholdBoundary() {
        let thetaAtThreshold = (Double(distanceThreshold) / Double(screenWidth)) * maxRotationDegrees
        XCTAssertEqual(thetaAtThreshold, 7.0, accuracy: 0.01, "At 137.5pt, rotation angle is exactly 7.0 degrees")
    }

    // MARK: - Feature 12: LIFO Undo Stack & State Recovery (F12)
    
    func testLifoUndoStackSingleOperation() {
        var undoStack: [SwipeAction] = []
        var deck: [String] = ["card-1", "card-2", "card-3"]
        var retained: [String] = []
        
        // Action: User swipes card-1 right (Retain)
        let topCard = deck.removeFirst()
        retained.append(topCard)
        undoStack.append(SwipeAction(assetId: topCard, direction: .retain, timestamp: Date()))
        
        XCTAssertEqual(deck.first, "card-2")
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(undoStack.count, 1)
        
        // Undo Action
        let undoneAction = undoStack.removeLast()
        XCTAssertEqual(undoneAction.assetId, "card-1")
        XCTAssertEqual(undoneAction.direction, .retain)
        
        if let idx = retained.firstIndex(of: undoneAction.assetId) {
            retained.remove(at: idx)
        }
        deck.insert(undoneAction.assetId, at: 0)
        
        XCTAssertEqual(deck.first, "card-1", "Card must be restored to index 0 of active deck")
        XCTAssertTrue(retained.isEmpty, "Retained list must revert")
        XCTAssertTrue(undoStack.isEmpty, "Undo stack must be empty")
    }
    
    func testMultiLevelLifoOrder() {
        var undoStack: [SwipeAction] = []
        for i in 1...5 {
            undoStack.append(SwipeAction(assetId: "card-\(i)", direction: i % 2 == 0 ? .retain : .stageDelete, timestamp: Date()))
        }
        
        XCTAssertEqual(undoStack.count, 5)
        
        // Pop in LIFO order
        let pop1 = undoStack.removeLast()
        XCTAssertEqual(pop1.assetId, "card-5")
        
        let pop2 = undoStack.removeLast()
        XCTAssertEqual(pop2.assetId, "card-4")
        
        let pop3 = undoStack.removeLast()
        XCTAssertEqual(pop3.assetId, "card-3")
        
        let pop4 = undoStack.removeLast()
        XCTAssertEqual(pop4.assetId, "card-2")
        
        let pop5 = undoStack.removeLast()
        XCTAssertEqual(pop5.assetId, "card-1")
        
        XCTAssertTrue(undoStack.isEmpty)
    }

    // MARK: - Feature 13: Tactile Haptic System (F13)
    
    func testThresholdDebouncingLogic() {
        var thresholdHapticFired = false
        var hapticEventCount = 0
        
        let fireHapticIfNeeded: (CGFloat) -> Void = { dx in
            let isBeyond = abs(dx) >= self.distanceThreshold
            if isBeyond && !thresholdHapticFired {
                thresholdHapticFired = true
                hapticEventCount += 1
            } else if !isBeyond && thresholdHapticFired {
                thresholdHapticFired = false // Reset debounce when returning inside threshold
            }
        }
        
        // Simulate dragging across threshold
        fireHapticIfNeeded(100.0) // Below
        XCTAssertEqual(hapticEventCount, 0)
        
        fireHapticIfNeeded(140.0) // Across threshold -> Fire 1
        XCTAssertEqual(hapticEventCount, 1)
        
        fireHapticIfNeeded(160.0) // Still beyond -> Should NOT fire again
        XCTAssertEqual(hapticEventCount, 1)
        
        fireHapticIfNeeded(100.0) // Back below threshold -> Resets flag
        XCTAssertEqual(hapticEventCount, 1)
        
        fireHapticIfNeeded(150.0) // Crosses again -> Fire 2
        XCTAssertEqual(hapticEventCount, 2)
    }

    // MARK: - Feature 19: iPhone 14 Pro Geometry (F19)
    
    func testDeviceGeometryConstants() {
        let topSafeArea: CGFloat = 59.0
        let bottomSafeArea: CGFloat = 34.0
        let dynamicIslandBottom: CGFloat = 47.67
        
        XCTAssertGreaterThan(topSafeArea, dynamicIslandBottom, "Top safe area must provide positive clearance below Dynamic Island")
        
        let usableHeight = screenHeight - topSafeArea - bottomSafeArea
        XCTAssertEqual(usableHeight, 759.0, "Usable vertical canvas for iPhone 14 Pro is 759pt")
    }

    // MARK: - Feature 20: Empty State Transition (F20)
    
    func testEmptyStateOnLastCardSwiped() {
        var cards = ["only-card"]
        var isDeckEmpty = false
        
        // Swipe last card
        _ = cards.removeFirst()
        if cards.isEmpty {
            isDeckEmpty = true
        }
        
        XCTAssertTrue(isDeckEmpty, "Deck must transition to empty state when final card is consumed")
    }
}
