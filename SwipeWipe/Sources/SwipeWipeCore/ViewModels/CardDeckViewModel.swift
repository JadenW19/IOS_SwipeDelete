//
//  CardDeckViewModel.swift
//  SwipeWipeCore
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import Foundation
import CoreGraphics
import Combine

/// Main coordinator managing 120Hz ProMotion gesture physics, 3-card sliding window hierarchy,
/// bi-directional decision engine commits, and LIFO undo stack restoration.
@MainActor
public final class CardDeckViewModel: ObservableObject {

    // MARK: - iPhone 14 Pro Geometry Constants (Display: 393 x 852 pt @ 460 ppi)

    public static let screenWidth: CGFloat = 393.0
    public static let screenHeight: CGFloat = 852.0
    public static let distanceThreshold: CGFloat = 137.5 // 393 * 0.35
    public static let velocityThreshold: CGFloat = 800.0 // pt/s
    public static let minFlickDistance: CGFloat = 35.0
    public static let maxRotationDegrees: Double = 20.0
    public static let topSafeArea: CGFloat = 59.0
    public static let bottomSafeArea: CGFloat = 34.0
    public static let dynamicIslandBottom: CGFloat = 47.67
    public static let usableHeight: CGFloat = 759.0

    // MARK: - Published State

    @Published public private(set) var cards: [PhotoAssetModel] = []
    @Published public private(set) var retainedAssets: [PhotoAssetModel] = []
    @Published public private(set) var undoStack: [SwipeAction] = []
    @Published public private(set) var state: CardDeckState = .idle
    @Published public private(set) var activeDragOffset: CGSize = .zero
    @Published public private(set) var activeDragVelocity: CGSize = .zero
    @Published public private(set) var visibleCards: [PhotoAssetModel] = []
    @Published public private(set) var canUndo: Bool = false

    // MARK: - Dependencies

    public let stagingStore: any StagedQueueStoreProtocol
    public let haptics: any HapticFeedbackServiceProtocol

    // MARK: - Initialization

    public init(
        initialCards: [PhotoAssetModel] = [],
        stagingStore: any StagedQueueStoreProtocol = StagedQueueStore(),
        haptics: any HapticFeedbackServiceProtocol = HapticFeedbackService()
    ) {
        self.cards = initialCards
        self.stagingStore = stagingStore
        self.haptics = haptics
        self.state = initialCards.isEmpty ? .empty : .idle
        self.visibleCards = Array(initialCards.prefix(3))
        self.canUndo = false
    }

    // MARK: - Computed Properties

    public var topCard: PhotoAssetModel? {
        cards.first
    }

    public var remainingCount: Int {
        cards.count
    }

    public var isEmpty: Bool {
        cards.isEmpty
    }

    public var currentDragProgress: Double {
        Self.calculateProgress(dx: activeDragOffset.width)
    }

    public var currentRotationAngle: Double {
        Self.calculateRotation(dx: activeDragOffset.width)
    }

    // MARK: - Static Mathematical Physics Helpers (120Hz Frame Budget < 0.05ms)

    /// Calculates dynamic rotation angle theta = (dx / screenWidth) * 20 degrees, clamped to [-20, 20].
    public static func calculateRotation(dx: CGFloat) -> Double {
        let ratio = max(min(Double(dx) / Double(screenWidth), 1.0), -1.0)
        return ratio * maxRotationDegrees
    }

    /// Calculates normalized drag progress p = clamp(|dx| / distanceThreshold, 0, 1).
    public static func calculateProgress(dx: CGFloat) -> Double {
        min(max(abs(Double(dx)) / Double(distanceThreshold), 0.0), 1.0)
    }

    /// Evaluates sliding 3-card window layout transforms: scale, y-offset, opacity, z-index, and rotation.
    public static func calculateCardStackTransforms(dx: CGFloat) -> [String: (scale: Double, offsetY: Double, opacity: Double, zIndex: Double, rotation: Double)] {
        let p = calculateProgress(dx: dx)
        return [
            "card_0": (
                scale: 1.0,
                offsetY: 0.0,
                opacity: 1.0,
                zIndex: 3.0,
                rotation: calculateRotation(dx: dx)
            ),
            "card_1": (
                scale: 0.94 + (0.06 * p),
                offsetY: 14.0 * (1.0 - p),
                opacity: 0.90 + (0.10 * p),
                zIndex: 2.0,
                rotation: 0.0
            ),
            "card_2": (
                scale: 0.88 + (0.06 * p),
                offsetY: 26.0 - (12.0 * p),
                opacity: 0.70 + (0.20 * p),
                zIndex: 1.0,
                rotation: 0.0
            )
        ]
    }

    /// Returns initial off-screen reverse entrance offset for undo animations.
    public static func undoEntranceOffset(for direction: SwipeDirection) -> CGSize {
        switch direction {
        case .retain:
            return CGSize(width: 490.0, height: 0.0)
        case .stageDelete:
            return CGSize(width: -490.0, height: 0.0)
        case .skip:
            return CGSize(width: 0.0, height: -600.0)
        }
    }

    // MARK: - Gesture Handling

    /// Updates drag translation and velocity during 120Hz gesture tracking.
    public func handleDragChanged(translation: CGSize, velocity: CGSize = .zero) {
        guard !cards.isEmpty else { return }
        self.state = .dragging
        self.activeDragOffset = translation
        self.activeDragVelocity = velocity
        haptics.updateThreshold(dx: Double(translation.width), threshold: Double(Self.distanceThreshold))
    }

    /// Overload accepting offset nomenclature conforming to interface contracts.
    public func handleDragChanged(offset: CGSize, velocity: CGSize = .zero) {
        handleDragChanged(translation: offset, velocity: velocity)
    }

    /// Evaluates gesture release physics and triggers decision commit or snapback rebound.
    @discardableResult
    public func handleDragEnded(translation: CGSize, velocity: CGSize = .zero) -> SwipeDirection? {
        guard !cards.isEmpty else { return nil }

        let dx = translation.width
        let vx = velocity.width

        // Commit criteria: Distance cutoff (>= 137.5pt) OR Velocity escape flick (>= 800pt/s with min 35pt travel)
        let commitRight = (dx >= Self.distanceThreshold) ||
            (vx >= Self.velocityThreshold && dx >= Self.minFlickDistance)
        let commitLeft = (dx <= -Self.distanceThreshold) ||
            (vx <= -Self.velocityThreshold && dx <= -Self.minFlickDistance)

        if commitRight {
            return swipeTopCard(direction: .retain)
        } else if commitLeft {
            return swipeTopCard(direction: .stageDelete)
        } else {
            // Rebound animation back to center rest
            self.activeDragOffset = .zero
            self.activeDragVelocity = .zero
            self.state = .idle
            return nil
        }
    }

    /// Overload accepting offset nomenclature conforming to interface contracts.
    @discardableResult
    public func handleDragEnded(offset: CGSize, velocity: CGSize = .zero) -> SwipeDirection? {
        handleDragEnded(translation: offset, velocity: velocity)
    }

    // MARK: - Action Execution & State Machine Transitions

    /// Programmatically commits a decision on the active top card.
    @discardableResult
    public func swipeTopCard(direction: SwipeDirection) -> SwipeDirection {
        guard !cards.isEmpty else { return direction }

        let top = cards.removeFirst()
        let action = SwipeAction(
            assetId: top.id,
            direction: direction,
            timestamp: Date(),
            byteSize: top.estimatedByteSize
        )
        undoStack.append(action)

        switch direction {
        case .retain:
            retainedAssets.append(top)

        case .stageDelete:
            let mediaType: StagedMediaType
            if top.mediaType == .video {
                mediaType = .video
            } else if top.isScreenshot {
                mediaType = .screenshot
            } else {
                mediaType = .photo
            }

            let stagedItem = StagedAssetItem(
                id: top.id,
                localIdentifier: top.localIdentifier,
                sourceBucketId: "active",
                creationDate: top.creationDate,
                mediaType: mediaType,
                byteSize: top.estimatedByteSize,
                isFavorite: top.isFavorite,
                isScreenshot: top.isScreenshot
            )
            _ = stagingStore.stageAsset(stagedItem)
            if top.isFavorite {
                haptics.triggerWarning()
            }

        case .skip:
            break
        }

        haptics.triggerCommit(direction: direction)
        self.activeDragOffset = .zero
        self.activeDragVelocity = .zero
        self.syncStackState()

        if cards.isEmpty {
            self.state = .empty
            haptics.triggerSuccess()
        } else {
            self.state = .idle
        }

        return direction
    }

    /// Reverses the most recent swipe action in LIFO order and restores the card to index 0.
    @discardableResult
    public func undoLastSwipe() -> PhotoAssetModel? {
        guard let action = undoStack.popLast() else {
            haptics.triggerWarning()
            return nil
        }

        var restoredAsset: PhotoAssetModel?

        switch action.direction {
        case .retain:
            if let index = retainedAssets.firstIndex(where: { $0.id == action.assetId }) {
                restoredAsset = retainedAssets.remove(at: index)
            }

        case .stageDelete:
            if let unstaged = stagingStore.unstageAsset(id: action.assetId) {
                restoredAsset = PhotoAssetModel(
                    id: unstaged.id,
                    localIdentifier: unstaged.localIdentifier,
                    creationDate: unstaged.creationDate,
                    estimatedByteSize: unstaged.byteSize,
                    isFavorite: unstaged.isFavorite
                )
            }

        case .skip:
            break
        }

        let assetToRestore = restoredAsset ?? PhotoAssetModel(
            id: action.assetId,
            localIdentifier: "ph-\(action.assetId)",
            creationDate: action.timestamp,
            estimatedByteSize: action.byteSize
        )

        cards.insert(assetToRestore, at: 0)
        haptics.triggerUndo()
        self.syncStackState()

        if state == .empty && !cards.isEmpty {
            self.state = .idle
        }

        return assetToRestore
    }

    /// Loads a fresh cohort of photo assets into the swiping deck.
    public func loadCohort(_ newCards: [PhotoAssetModel]) {
        self.cards = newCards
        self.activeDragOffset = .zero
        self.activeDragVelocity = .zero
        self.syncStackState()
        self.state = newCards.isEmpty ? .empty : .idle
    }

    /// Resets the deck state to initial configuration.
    public func reset() {
        self.cards.removeAll()
        self.retainedAssets.removeAll()
        self.undoStack.removeAll()
        self.activeDragOffset = .zero
        self.activeDragVelocity = .zero
        self.syncStackState()
        self.state = .empty
    }

    // MARK: - Private State Synchronization

    private func syncStackState() {
        self.visibleCards = Array(cards.prefix(3))
        self.canUndo = !undoStack.isEmpty
    }
}
