//
//  MainDeckContainerView.swift
//  SwipeWipeApp
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import SwiftUI
import SwipeWipeCore

/// Full-screen root container integrating the Dynamic Island header, 120Hz gesture deck,
/// bottom action bar with LIFO undo controls, and the non-destructive review queue.
public struct MainDeckContainerView: View {

    @StateObject private var deckViewModel: CardDeckViewModel
    @StateObject private var reviewViewModel: ReviewQueueViewModel
    @StateObject private var libraryViewModel: LibraryViewModel

    @State private var isPresentingReviewSheet: Bool = false
    @State private var isPresentingMonthPicker: Bool = false
    @State private var selectedTab: Int = 0

    public init(
        photoProvider: any PhotoLibraryProviding = PhotoLibraryService(),
        stagingStore: any StagedQueueStoreProtocol = StagedQueueStore(),
        haptics: any HapticFeedbackServiceProtocol = HapticFeedbackService()
    ) {
        let deck = CardDeckViewModel(initialCards: [], stagingStore: stagingStore, haptics: haptics)
        let deletion = NativeBatchDeletionService(photoProvider: photoProvider)
        let review = ReviewQueueViewModel(stagingStore: stagingStore, deletionService: deletion, haptics: haptics)
        let library = LibraryViewModel(photoProvider: photoProvider)

        _deckViewModel = StateObject(wrappedValue: deck)
        _reviewViewModel = StateObject(wrappedValue: review)
        _libraryViewModel = StateObject(wrappedValue: library)
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Dynamic Island Adaptive Header
                DynamicIslandHeaderView(
                    title: libraryViewModel.selectedBucket?.title ?? "October 2026",
                    progressText: "\(deckViewModel.cards.count) remaining",
                    reclaimedStorageText: reviewViewModel.snapshot.formattedSize,
                    onSelectMonth: {
                        isPresentingMonthPicker = true
                    }
                )

                // Main Swiping Deck or Clutter Hub
                TabView(selection: $selectedTab) {
                    // Tab 0: Monthly Deck
                    CardStackView(viewModel: deckViewModel)
                        .tag(0)

                    // Tab 1: Clutter Hub
                    ClutterHubView(libraryViewModel: libraryViewModel) { category in
                        Task {
                            if let assets = try? await libraryViewModel.photoProvider.fetchClutterCategory(category) {
                                deckViewModel.loadCohort(assets)
                                selectedTab = 0
                            }
                        }
                    }
                    .tag(1)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif

                // Bottom Action Controls Bar
                HStack(spacing: 24) {
                    // Undo Button
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            deckViewModel.undoLastSwipe()
                            reviewViewModel.refresh()
                        }
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(deckViewModel.canUndo ? .primary : .secondary.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                    .disabled(!deckViewModel.canUndo)

                    // Trash Button (Swipe Left programmatic trigger)
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                            deckViewModel.swipeTopCard(direction: .stageDelete)
                            reviewViewModel.refresh()
                        }
                    }) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.red)
                            .frame(width: 64, height: 64)
                            .background(Color.red.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .disabled(deckViewModel.isEmpty)

                    // Keep Button (Swipe Right programmatic trigger)
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                            deckViewModel.swipeTopCard(direction: .retain)
                        }
                    }) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.green)
                            .frame(width: 64, height: 64)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .disabled(deckViewModel.isEmpty)

                    // Review Queue Drawer FAB
                    Button(action: {
                        isPresentingReviewSheet = true
                    }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.accentColor)
                                .frame(width: 50, height: 50)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Circle())

                            if reviewViewModel.snapshot.totalCount > 0 {
                                Text("\(reviewViewModel.snapshot.totalCount)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(white: 1.0))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $isPresentingReviewSheet) {
            ReviewQueueSheet(viewModel: reviewViewModel)
        }
        .sheet(isPresented: $isPresentingMonthPicker) {
            NavigationStack {
                List(libraryViewModel.monthlyBuckets) { bucket in
                    Button(action: {
                        Task {
                            await libraryViewModel.selectBucket(bucket)
                            if let assets = try? await libraryViewModel.photoProvider.fetchAssets(for: bucket.identifier) {
                                deckViewModel.loadCohort(assets)
                            }
                        }
                        isPresentingMonthPicker = false
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bucket.title)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)

                                Text("\(bucket.assetCount) photos • \(SizeFormatter.formatDeterministic(bytes: bucket.totalByteSizeEstimate))")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if libraryViewModel.selectedBucket?.id == bucket.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 14, weight: .bold))
                            }
                        }
                    }
                }
                .navigationTitle("Select Month")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            }
        }
        .task {
            await libraryViewModel.requestAuthorization()
            await libraryViewModel.fetchBuckets()
            if let first = libraryViewModel.monthlyBuckets.first {
                await libraryViewModel.selectBucket(first)
                if let assets = try? await libraryViewModel.photoProvider.fetchAssets(for: first.identifier) {
                    deckViewModel.loadCohort(assets)
                }
            }
        }
    }
}
