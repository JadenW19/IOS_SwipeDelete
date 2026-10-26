//
//  ClutterHubView.swift
//  SwipeWipeApp
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import SwiftUI
import SwipeWipeCore

/// Clutter cleanup hub categorizing screenshots, duplicate clusters, and large videos.
public struct ClutterHubView: View {

    @ObservedObject public var libraryViewModel: LibraryViewModel
    public let onSelectCategory: (ClutterCategoryType) -> Void

    public init(
        libraryViewModel: LibraryViewModel,
        onSelectCategory: @escaping (ClutterCategoryType) -> Void = { _ in }
    ) {
        self.libraryViewModel = libraryViewModel
        self.onSelectCategory = onSelectCategory
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clutter Cleaner")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Reclaim gigabytes by targeting high-impact categories.")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // Category Cards Grid
                VStack(spacing: 14) {
                    categoryCard(
                        type: .screenshots,
                        title: "Screenshots",
                        systemIcon: "camera.viewfinder",
                        accentColor: .purple,
                        itemCount: libraryViewModel.clutterCategories[.screenshots]?.assetCount ?? 0,
                        bytes: libraryViewModel.clutterCategories[.screenshots]?.totalByteSize ?? 0
                    )

                    categoryCard(
                        type: .duplicates,
                        title: "Similar & Duplicates",
                        systemIcon: "square.on.square",
                        accentColor: .blue,
                        itemCount: libraryViewModel.clutterCategories[.duplicates]?.assetCount ?? 0,
                        bytes: libraryViewModel.clutterCategories[.duplicates]?.totalByteSize ?? 0
                    )

                    categoryCard(
                        type: .largeVideos,
                        title: "Large Videos",
                        systemIcon: "video.fill",
                        accentColor: .orange,
                        itemCount: libraryViewModel.clutterCategories[.largeVideos]?.assetCount ?? 0,
                        bytes: libraryViewModel.clutterCategories[.largeVideos]?.totalByteSize ?? 0
                    )

                    categoryCard(
                        type: .bursts,
                        title: "Burst Photos",
                        systemIcon: "square.stack.3d.down.right.fill",
                        accentColor: .indigo,
                        itemCount: libraryViewModel.clutterCategories[.bursts]?.assetCount ?? 0,
                        bytes: libraryViewModel.clutterCategories[.bursts]?.totalByteSize ?? 0
                    )
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 30)
        }
    }

    private func categoryCard(
        type: ClutterCategoryType,
        title: String,
        systemIcon: String,
        accentColor: Color,
        itemCount: Int,
        bytes: Int64
    ) -> some View {
        Button(action: {
            onSelectCategory(type)
        }) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 52, height: 52)

                    Image(systemName: systemIcon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(accentColor)
                }

                // Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("\(itemCount) items • \(SizeFormatter.formatDeterministic(bytes: bytes))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
