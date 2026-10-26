//
//  ReviewQueueSheet.swift
//  SwipeWipeApp
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import SwiftUI
import SwipeWipeCore

/// Non-destructive review drawer modal displaying staged deletion candidates.
/// Features:
/// - Total space to be reclaimed header banner
/// - 3-column scrollable grid of staged photo thumbnails
/// - Individual unstaging actions (restore to Deck or Retained)
/// - Bulk clear all button
/// - Favorite asset warning banner
/// - Explicit double-confirmation dialog before executing native batch deletion
public struct ReviewQueueSheet: View {

    // MARK: - View Model & Environment

    @ObservedObject public var viewModel: ReviewQueueViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Grid Layout Configuration (3-Column Responsive Grid)

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    // MARK: - Initialization

    public init(viewModel: ReviewQueueViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - View Body

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Banner: Staged Summary & Clear All Button
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(viewModel.snapshot.totalCount) Items Staged")
                            .font(.system(size: 20, weight: .bold, design: .rounded))

                        Text("Total Reclaimable: \(viewModel.snapshot.formattedSize)")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if !viewModel.snapshot.isEmpty {
                        Button(role: .destructive, action: {
                            viewModel.clearAll()
                        }) {
                            Text("Clear All")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemBackground))

                // Favorite Warning Guard Banner
                if viewModel.snapshot.favoriteCount > 0 {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.yellow)

                        Text("Includes \(viewModel.snapshot.favoriteCount) favorite photo(s). They will be permanently deleted unless unstaged.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.yellow.opacity(0.18))
                }

                // Error Message Banner (e.g. system permission denial)
                if let errorMsg = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(errorMsg)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.12))
                }

                // Main Content: Thumbnail Grid or Empty Placeholder
                if viewModel.snapshot.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "tray")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(.secondary)
                        Text("Review Queue is Empty")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("Swipe left on photos to stage them for deletion.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.8))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(viewModel.snapshot.items) { item in
                                stagedThumbnailCell(for: item)
                            }
                        }
                        .padding(14)
                    }
                }

                // Bottom Batch Deletion Execution Button
                if !viewModel.snapshot.isEmpty {
                    VStack {
                        Button(action: {
                            viewModel.isPresentingConfirmationDialog = true
                        }) {
                            HStack(spacing: 8) {
                                if viewModel.isDeleting {
                                    ProgressView()
                                        .tint(Color(white: 1.0))
                                } else {
                                    Image(systemName: "trash.fill")
                                    Text("Delete \(viewModel.snapshot.totalCount) Photos (\(viewModel.snapshot.formattedSize))")
                                }
                            }
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(Color(white: 1.0))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.red.opacity(0.35), radius: 8, x: 0, y: 4)
                        }
                        .disabled(viewModel.isDeleting)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle("Review Deletions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                }
                #endif
            }
            // Explicit In-App Double-Confirmation Dialog before invoking native PhotoKit API
            .confirmationDialog(
                "Delete \(viewModel.snapshot.totalCount) Photos from Camera Roll?",
                isPresented: $viewModel.isPresentingConfirmationDialog,
                titleVisibility: .visible
            ) {
                Button("Delete \(viewModel.snapshot.totalCount) Photos", role: .destructive) {
                    Task {
                        let outcome = await viewModel.executeBatchDeletion()
                        if case .success = outcome {
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.dismissConfirmation()
                }
            } message: {
                Text("This action will trigger the native iOS system confirmation dialog. If you cancel, your queue will remain untouched.")
            }
        }
    }

    // MARK: - Staged Thumbnail Cell Component

    @ViewBuilder
    private func stagedThumbnailCell(for item: StagedAssetItem) -> some View {
        ZStack(alignment: .bottom) {
            // Background Thumbnail Placeholder
            ZStack(alignment: .topTrailing) {
                Color(.secondarySystemBackground)

                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: item.mediaType == .video ? "video.fill" : "photo.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.8))
                    Spacer()
                }

                // Top Media Subtype Badges
                HStack(spacing: 4) {
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.pink)
                    }
                    if item.isScreenshot {
                        Text("SHOT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(white: 1.0))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.85))
                            .clipShape(Capsule())
                    }
                }
                .padding(6)
            }
            .frame(height: 120)

            // Bottom Gradient Overlay with Size & Unstage Menu
            HStack(alignment: .bottom) {
                Text(SizeFormatter.formatDeterministic(bytes: item.byteSize))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(white: 1.0))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(white: 0.0, opacity: 0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Spacer()

                // Individual Unstaging Actions: Restore to Deck or Retained
                Menu {
                    Button(action: {
                        viewModel.unstageToRetained(id: item.id)
                    }) {
                        Label("Restore to Kept (Retain)", systemImage: "heart.fill")
                    }

                    Button(action: {
                        viewModel.unstageToDeck(id: item.id)
                    }) {
                        Label("Restore to Deck", systemImage: "arrow.uturn.backward")
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(white: 1.0))
                        .background(Circle().fill(Color.blue))
                }
            }
            .padding(6)
            .background(
                LinearGradient(
                    colors: [Color(white: 0.0, opacity: 0.0), Color(white: 0.0, opacity: 0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
