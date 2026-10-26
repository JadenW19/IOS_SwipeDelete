//
//  EmptyStateView.swift
//  SwipeWipeApp
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import SwiftUI
import SwipeWipeCore

/// Celebration completion view displayed when a monthly bucket or clutter category is completely cleaned.
/// Displays a celebration animation/icon, total statistics summary (reviewed count, staged count,
/// storage reclaimed), and actions to return to the library overview or advance to the next cohort.
public struct EmptyStateView: View {

    // MARK: - Properties

    public let title: String
    public let subtitle: String
    public let reviewedCount: Int
    public let stagedCount: Int
    public let reclaimedSpace: String
    public let onReturnToLibrary: () -> Void
    public let onNextMonth: () -> Void

    // MARK: - Initialization

    public init(
        title: String = "Cohort Cleared! 🎉",
        subtitle: String = "All photos in this cohort have been completely reviewed.",
        reviewedCount: Int = 0,
        stagedCount: Int = 0,
        reclaimedSpace: String = "",
        onReturnToLibrary: @escaping () -> Void = {},
        onNextMonth: @escaping () -> Void = {}
    ) {
        self.title = title
        self.subtitle = subtitle
        self.reviewedCount = reviewedCount
        self.stagedCount = stagedCount
        self.reclaimedSpace = reclaimedSpace
        self.onReturnToLibrary = onReturnToLibrary
        self.onNextMonth = onNextMonth
    }

    // MARK: - View Body

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Celebration Icon with Glow
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 120, height: 120)

                Circle()
                    .stroke(Color.green.opacity(0.3), lineWidth: 3)
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(.green)
            }
            .padding(.bottom, 6)

            // Title & Subtitle
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            // Total Statistics Summary Card (if statistics are provided)
            if reviewedCount > 0 || stagedCount > 0 || !reclaimedSpace.isEmpty {
                HStack(spacing: 20) {
                    statColumn(title: "Reviewed", value: "\(reviewedCount)")
                    Divider()
                        .frame(height: 36)
                    statColumn(title: "Staged", value: "\(stagedCount)")
                    Divider()
                        .frame(height: 36)
                    statColumn(title: "Reclaimed", value: reclaimedSpace.isEmpty ? "0 B" : reclaimedSpace)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
            }

            Spacer()

            // Navigation Actions: Return to Library Overview & Review Next Month
            VStack(spacing: 12) {
                Button(action: onReturnToLibrary) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Return to Library Overview")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color(white: 1.0))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                    .shadow(color: Color.accentColor.opacity(0.32), radius: 8, x: 0, y: 4)
                }

                Button(action: onNextMonth) {
                    HStack(spacing: 6) {
                        Text("Review Next Cohort")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}
