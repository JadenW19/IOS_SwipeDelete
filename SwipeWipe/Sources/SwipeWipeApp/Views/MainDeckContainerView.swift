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

    /// Completion tracking for the cohort currently loaded in the deck.
    @State private var currentCohortKey: String? = nil
    @State private var currentCohortTitle: String? = nil
    @State private var completedKeys: Set<String> = []
    private let completionStore = CompletionStore()

    private var onThisDayAssets: [PhotoAssetModel] {
        OnThisDay.assets(in: libraryViewModel.monthlyBuckets, on: Date())
    }

    private var onThisDayKey: String {
        OnThisDay.completionKey(for: Date())
    }

    private var todaySubtitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: Date())
    }

    private func loadCohort(_ assets: [PhotoAssetModel], key: String?, title: String?) {
        currentCohortKey = assets.isEmpty ? nil : key
        currentCohortTitle = title
        deckViewModel.loadCohort(assets)
        reviewViewModel.refresh()
    }

    private func advanceToNextCohort() {
        let buckets = libraryViewModel.monthlyBuckets
        guard !buckets.isEmpty else {
            isPresentingMonthPicker = true
            return
        }

        // Find the next uncompleted monthly bucket (or the next bucket in order)
        let currentIndex = buckets.firstIndex { OnThisDay.completionKey(for: $0.identifier) == currentCohortKey }
        let startIndex = currentIndex.map { $0 + 1 } ?? 0

        let nextBucket: MonthlyBucket? = {
            if startIndex < buckets.count {
                if let uncompleted = buckets[startIndex...].first(where: { !completedKeys.contains(OnThisDay.completionKey(for: $0.identifier)) }) {
                    return uncompleted
                }
                return buckets[startIndex]
            }
            return buckets.first(where: { !completedKeys.contains(OnThisDay.completionKey(for: $0.identifier)) }) ?? buckets.first
        }()

        guard let bucket = nextBucket else { return }
        Task {
            await libraryViewModel.selectBucket(bucket)
            if let assets = try? await libraryViewModel.photoProvider.fetchAssets(for: bucket.identifier) {
                loadCohort(assets, key: OnThisDay.completionKey(for: bucket.identifier), title: bucket.title)
            }
        }
    }

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
                    title: currentCohortTitle ?? libraryViewModel.selectedBucket?.title ?? "Photos",
                    progressText: "\(deckViewModel.cards.count) remaining",
                    reclaimedStorageText: deckViewModel.stagingStore.snapshot.formattedSize,
                    onSelectMonth: {
                        isPresentingMonthPicker = true
                    },
                    onOpenReviewDrawer: {
                        isPresentingReviewSheet = true
                    }
                )
                .zIndex(10)

                // Clean Main Swiping Deck
                CardStackView(
                    viewModel: deckViewModel,
                    onReturnToLibrary: {
                        isPresentingMonthPicker = true
                    },
                    onNextMonth: {
                        advanceToNextCohort()
                    }
                )
                    .zIndex(1)

                // Bottom Action Controls Bar
                HStack(spacing: 24) {
                    // Undo Button
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            _ = deckViewModel.undoLastSwipe()
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
                            _ = deckViewModel.swipeTopCard(direction: .stageDelete)
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
                            _ = deckViewModel.swipeTopCard(direction: .retain)
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

                            if deckViewModel.stagingStore.snapshot.totalCount > 0 {
                                Text("\(deckViewModel.stagingStore.snapshot.totalCount)")
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
                .zIndex(10)
            }
        }
        .sheet(isPresented: $isPresentingReviewSheet) {
            ReviewQueueSheet(viewModel: reviewViewModel)
        }
        .sheet(isPresented: $isPresentingMonthPicker) {
            cohortSelectorSheet
        }
        // Keep the review queue (staged count / size) in sync and persist cohort completion on the final swipe.
        .onChange(of: deckViewModel.undoStack.count) { _, newCount in
            reviewViewModel.refresh()
            if deckViewModel.cards.isEmpty && newCount > 0, let key = currentCohortKey {
                completionStore.markCompleted(key)
                completedKeys = completionStore.allCompleted
            }
        }
        // Fallback completion observer when the card array transitions to empty.
        .onChange(of: deckViewModel.cards.count) { oldCount, newCount in
            if oldCount > 0 && newCount == 0, let key = currentCohortKey {
                completionStore.markCompleted(key)
                completedKeys = completionStore.allCompleted
            }
        }
        .task {
            completedKeys = completionStore.allCompleted
            await libraryViewModel.requestAuthorization()
            await libraryViewModel.fetchBuckets()
            let buckets = libraryViewModel.monthlyBuckets
            let initial = buckets.first(where: { !completedKeys.contains(OnThisDay.completionKey(for: $0.identifier)) }) ?? buckets.first
            if let first = initial {
                await libraryViewModel.selectBucket(first)
                if let assets = try? await libraryViewModel.photoProvider.fetchAssets(for: first.identifier) {
                    loadCohort(assets, key: OnThisDay.completionKey(for: first.identifier), title: first.title)
                }
            }
            await OnThisDayNotifier.scheduleUpcoming(buckets: libraryViewModel.monthlyBuckets)
        }
    }

    // MARK: - Unified Cohort / Memories / Clutter Selector Sheet

    private var cohortSelectorSheet: some View {
        NavigationStack {
            List {
                // Section 1: On This Day
                Section("Memories") {
                    Button(action: {
                        loadCohort(onThisDayAssets, key: onThisDayKey, title: "On This Day")
                        isPresentingMonthPicker = false
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.orange)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("On This Day (\(todaySubtitle))")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)

                                Text(onThisDayAssets.isEmpty
                                    ? "No photos from earlier years today"
                                    : "\(onThisDayAssets.count) photos to look back on today")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if completedKeys.contains(onThisDayKey) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                    Text("Completed")
                                }
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.14))
                                .clipShape(Capsule())
                            } else if currentCohortKey == onThisDayKey {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 14, weight: .bold))
                            }
                        }
                    }
                    .disabled(onThisDayAssets.isEmpty)
                }

                // Section 2: Clutter Categories
                Section("Clutter Cleaner") {
                    clutterRow(type: .screenshots, title: "Screenshots", icon: "camera.viewfinder", color: .purple)
                    clutterRow(type: .duplicates, title: "Similar & Duplicates", icon: "square.on.square", color: .blue)
                    clutterRow(type: .largeVideos, title: "Large Videos", icon: "video.fill", color: .orange)
                    clutterRow(type: .bursts, title: "Burst Photos", icon: "square.stack.3d.down.right.fill", color: .indigo)
                }

                // Section 3: Monthly Cohorts
                Section("By Month") {
                    ForEach(libraryViewModel.monthlyBuckets) { bucket in
                        let bucketKey = OnThisDay.completionKey(for: bucket.identifier)
                        Button(action: {
                            Task {
                                await libraryViewModel.selectBucket(bucket)
                                if let assets = try? await libraryViewModel.photoProvider.fetchAssets(for: bucket.identifier) {
                                    loadCohort(assets, key: bucketKey, title: bucket.title)
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

                                if completedKeys.contains(bucketKey) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.seal.fill")
                                        Text("Completed")
                                    }
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.14))
                                    .clipShape(Capsule())
                                } else if currentCohortKey == bucketKey {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .font(.system(size: 14, weight: .bold))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Deck")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresentingMonthPicker = false
                    }
                    .font(.system(size: 16, weight: .bold))
                }
            }
        }
    }

    private func clutterRow(type: ClutterCategoryType, title: String, icon: String, color: Color) -> some View {
        let summary = libraryViewModel.clutterCategories[type]
        let count = summary?.assetCount ?? 0
        let bytes = summary?.totalByteSize ?? 0

        return Button(action: {
            Task {
                if let assets = try? await libraryViewModel.photoProvider.fetchClutterCategory(type) {
                    loadCohort(assets, key: nil, title: title)
                }
            }
            isPresentingMonthPicker = false
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("\(count) items • \(SizeFormatter.formatDeterministic(bytes: bytes))")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if currentCohortTitle == title {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 14, weight: .bold))
                }
            }
        }
    }
}
