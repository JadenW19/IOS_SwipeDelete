//
//  SwipeWipeApp.swift
//  SwipeWipeApp
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import SwiftUI
import SwipeWipeCore

/// Root application entry point for SwipeWipe on iOS 27.0.1+ / iPhone 14 Pro.
/// Implements full dependency injection for PhotoKit ingestion, 120Hz ProMotion card deck,
/// non-destructive staging queue, and deletion safety services.
@main
public struct SwipeWipeApp: App {

    // MARK: - Core Dependencies

    public let photoProvider: any PhotoLibraryProviding
    public let stagingStore: any StagedQueueStoreProtocol
    public let haptics: any HapticFeedbackServiceProtocol
    public let deletionService: any BatchDeletionServiceProtocol

    // MARK: - ViewModels (Injected across Scene Hierarchy)

    @StateObject public var libraryViewModel: LibraryViewModel
    @StateObject public var cardDeckViewModel: CardDeckViewModel
    @StateObject public var reviewQueueViewModel: ReviewQueueViewModel

    // MARK: - Initialization & Dependency Injection

    public init() {
        // Detect automated test / preview flags or default to native PhotoLibraryService
        let isMockMode = CommandLine.arguments.contains("-mock") ||
            ProcessInfo.processInfo.environment["SWIPEWIPE_USE_MOCKS"] == "1"

        let provider: any PhotoLibraryProviding = isMockMode
            ? MockPhotoProvider()
            : PhotoLibraryService()

        let store: any StagedQueueStoreProtocol = StagedQueueStore()
        let hapticDriver: any HapticFeedbackServiceProtocol = HapticFeedbackService()
        let deletion: any BatchDeletionServiceProtocol = NativeBatchDeletionService(photoProvider: provider)

        self.photoProvider = provider
        self.stagingStore = store
        self.haptics = hapticDriver
        self.deletionService = deletion

        _libraryViewModel = StateObject(
            wrappedValue: LibraryViewModel(photoProvider: provider)
        )
        _cardDeckViewModel = StateObject(
            wrappedValue: CardDeckViewModel(
                initialCards: [],
                stagingStore: store,
                haptics: hapticDriver
            )
        )
        _reviewQueueViewModel = StateObject(
            wrappedValue: ReviewQueueViewModel(
                stagingStore: store,
                deletionService: deletion,
                haptics: hapticDriver
            )
        )
    }

    /// Custom initializer allowing programmatic dependency injection for integration tests
    public init(
        photoProvider: any PhotoLibraryProviding,
        stagingStore: any StagedQueueStoreProtocol = StagedQueueStore(),
        haptics: any HapticFeedbackServiceProtocol = HapticFeedbackService()
    ) {
        let deletion = NativeBatchDeletionService(photoProvider: photoProvider)

        self.photoProvider = photoProvider
        self.stagingStore = stagingStore
        self.haptics = haptics
        self.deletionService = deletion

        _libraryViewModel = StateObject(
            wrappedValue: LibraryViewModel(photoProvider: photoProvider)
        )
        _cardDeckViewModel = StateObject(
            wrappedValue: CardDeckViewModel(
                initialCards: [],
                stagingStore: stagingStore,
                haptics: haptics
            )
        )
        _reviewQueueViewModel = StateObject(
            wrappedValue: ReviewQueueViewModel(
                stagingStore: stagingStore,
                deletionService: deletion,
                haptics: haptics
            )
        )
    }

    // MARK: - App Scene Hierarchy

    public var body: some Scene {
        WindowGroup {
            MainDeckContainerView(
                photoProvider: photoProvider,
                stagingStore: stagingStore,
                haptics: haptics
            )
            .environmentObject(libraryViewModel)
            .environmentObject(cardDeckViewModel)
            .environmentObject(reviewQueueViewModel)
        }
    }
}
