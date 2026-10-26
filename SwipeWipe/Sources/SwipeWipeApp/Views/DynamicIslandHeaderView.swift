//
//  DynamicIslandHeaderView.swift
//  SwipeWipeApp
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import SwiftUI
import SwipeWipeCore

/// Header component styled specifically for iPhone 14 Pro (393pt canvas, 120Hz ProMotion).
/// Provides exact clearance for the Dynamic Island (126pt × 36.67pt pill cutout, 59pt top safe area),
/// status bar integration, chronological month / clutter category title, live progress counter,
/// and an interactive staged storage pill badge opening the review drawer.
public struct DynamicIslandHeaderView: View {

    // MARK: - Hardware Geometry Specifications (iPhone 14 Pro)

    public static let topSafeAreaInset: CGFloat = 59.0
    public static let dynamicIslandWidth: CGFloat = 126.0
    public static let dynamicIslandHeight: CGFloat = 36.67
    public static let dynamicIslandBottom: CGFloat = 47.67

    // MARK: - Properties

    public let title: String
    public let progressText: String
    public let reclaimedStorageText: String
    public let onSelectMonth: () -> Void
    public let onOpenReviewDrawer: () -> Void

    // MARK: - Initialization

    public init(
        title: String,
        progressText: String,
        reclaimedStorageText: String,
        onSelectMonth: @escaping () -> Void = {},
        onOpenReviewDrawer: @escaping () -> Void = {}
    ) {
        self.title = title
        self.progressText = progressText
        self.reclaimedStorageText = reclaimedStorageText
        self.onSelectMonth = onSelectMonth
        self.onOpenReviewDrawer = onOpenReviewDrawer
    }

    // MARK: - View Body

    public var body: some View {
        VStack(spacing: 8) {
            // Hardware Safe Area Clearance: 59pt top inset clearance for Dynamic Island
            Spacer()
                .frame(height: Self.topSafeAreaInset)

            HStack(alignment: .center, spacing: 10) {
                // Month / Clutter Category Selector Button
                Button(action: onSelectMonth) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Select Cohort or Category")

                Spacer()

                // Live Progress Counter (e.g. "12 / 48" or "38 remaining")
                Text(progressText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())

                // Staged Space Pill Badge & Review Drawer Trigger
                Button(action: onOpenReviewDrawer) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(hasStagedItems ? .red : .secondary)

                        if hasStagedItems {
                            Text(reclaimedStorageText)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.red)
                        } else {
                            Text("0 B")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(hasStagedItems ? Color.red.opacity(0.12) : Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(hasStagedItems ? Color.red.opacity(0.28) : Color(white: 0.0, opacity: 0.0), lineWidth: 1)
                    )
                }
                .accessibilityLabel("Open Review Drawer. Total staged: \(reclaimedStorageText)")
            }
            .padding(.horizontal, 16)
        }
    }

    private var hasStagedItems: Bool {
        !reclaimedStorageText.isEmpty && reclaimedStorageText != "0 B"
    }
}
