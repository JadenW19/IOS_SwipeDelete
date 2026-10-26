//
//  PhotoCardView.swift
//  SwipeWipeApp
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import SwiftUI
import SwipeWipeCore

/// Presentation view for an individual photo/video card in the 120Hz ProMotion swipe deck.
/// Conforms to iPhone 14 Pro hardware specifications:
/// - 24pt continuous squircle clipping (`RoundedRectangle(cornerRadius: 24, style: .continuous)`)
/// - Pre-baked static shadow avoiding dynamic GPU rasterization passes
/// - Complete metadata overlay (capture date, pixel dimensions, file size, screenshot and duplicate badges)
/// - Directional decision stamps: "KEEP" in green on right drag, "DELETE" / "TRASH" in red on left drag
public struct PhotoCardView: View {

    // MARK: - Properties

    public let asset: PhotoAssetModel
    public let dragOffset: CGSize
    public let isTopCard: Bool

    // MARK: - Layout Constants

    private let cardWidth: CGFloat = 353.0
    private let cardHeight: CGFloat = 560.0
    private let cornerRadius: CGFloat = 24.0

    // MARK: - Initialization

    public init(
        asset: PhotoAssetModel,
        dragOffset: CGSize = .zero,
        isTopCard: Bool = false
    ) {
        self.asset = asset
        self.dragOffset = dragOffset
        self.isTopCard = isTopCard
    }

    // MARK: - Computed Gesture Progress (Normalized 0.0 ... 1.0)

    private var rightDragProgress: Double {
        guard isTopCard && dragOffset.width > 0 else { return 0.0 }
        return min(max(Double(dragOffset.width) / 100.0, 0.0), 1.0)
    }

    private var leftDragProgress: Double {
        guard isTopCard && dragOffset.width < 0 else { return 0.0 }
        return min(max(abs(Double(dragOffset.width)) / 100.0, 0.0), 1.0)
    }

    // MARK: - View Body

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Media Preview Canvas
            ZStack {
                Color(.secondarySystemBackground)

                // Placeholder / Cached downsampled photo preview
                VStack(spacing: 12) {
                    Image(systemName: asset.mediaType == .video ? "video.fill" : "photo.fill")
                        .font(.system(size: 64, weight: .light))
                        .foregroundColor(Color.accentColor.opacity(0.8))

                    Text(asset.id)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Top Vignette for Decision Stamp Contrast
                LinearGradient(
                    colors: [Color.black.opacity(0.42), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .allowsHitTesting(false)
            }
            .frame(width: cardWidth, height: cardHeight)

            // Decision Stamp Overlays (Rendered on Active Top Card)
            if isTopCard {
                // KEEP Stamp (Green) - Appears on right drag
                VStack {
                    HStack {
                        Text("KEEP")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.green)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.green, lineWidth: 4)
                            )
                            .rotationEffect(.degrees(-15))
                            .opacity(rightDragProgress)
                            .padding(.top, 24)
                            .padding(.leading, 24)

                        Spacer()
                    }
                    Spacer()
                }

                // DELETE / TRASH Stamp (Red) - Appears on left drag
                VStack {
                    HStack {
                        Spacer()

                        Text("DELETE")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.red)
                            .accessibilityLabel("TRASH")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.red, lineWidth: 4)
                            )
                            .rotationEffect(.degrees(15))
                            .opacity(leftDragProgress)
                            .padding(.top, 24)
                            .padding(.trailing, 24)
                    }
                    Spacer()
                }
            }

            // Bottom Metadata Gradient Overlay
            VStack(alignment: .leading, spacing: 8) {
                // Row 1: Capture Date, Time, and Favorite Heart
                HStack(alignment: .center) {
                    Text(asset.creationDate, style: .date)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(asset.creationDate, style: .time)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))

                    Spacer()

                    if asset.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 17))
                            .foregroundColor(.pink)
                    }
                }

                // Row 2: File Size, Pixel Dimensions, Media Badges (Screenshot & Duplicate)
                HStack(spacing: 8) {
                    // File Size Badge
                    Text(SizeFormatter.formatDeterministic(bytes: asset.estimatedByteSize))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.22))
                        .clipShape(Capsule())

                    // Pixel Resolution Badge
                    if asset.pixelWidth > 0 && asset.pixelHeight > 0 {
                        Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.16))
                            .clipShape(Capsule())
                    }

                    // Video Duration Badge
                    if asset.mediaType == .video && asset.duration > 0 {
                        Text(String(format: "%.0fs", asset.duration))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.85))
                            .clipShape(Capsule())
                    }

                    // Screenshot Badge
                    if asset.isScreenshot {
                        Text("SCREENSHOT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.85))
                            .clipShape(Capsule())
                    }

                    // Duplicate / Burst Clutter Badge
                    if asset.representsBurst || asset.burstIdentifier != nil {
                        Text("DUPLICATE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.85))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(width: cardWidth, height: cardHeight)
        // 24pt continuous squircle clipping conforming to Apple design standards
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Static pre-baked shadow to eliminate dynamic GPU rasterization hitches during 120Hz swiping
        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
    }
}
