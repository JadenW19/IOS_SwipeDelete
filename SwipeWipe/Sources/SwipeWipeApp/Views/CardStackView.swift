//
//  CardStackView.swift
//  SwipeWipeApp
//
//  Created for SwipeWipe Native iOS Rebuild (Target: iOS 27.0.1+ / iPhone 14 Pro)
//

import SwiftUI
import SwipeWipeCore

/// Sliding 3-card window interactive swipe deck with 120Hz ProMotion response.
/// Implements dynamic rotation physics, real-time depth scaling, isolated gesture bindings,
/// and an integrated bottom floating control bar (Undo, Keep, and Trash buttons).
public struct CardStackView: View {

    // MARK: - View Model & Properties

    @ObservedObject public var viewModel: CardDeckViewModel
    public let showsControlBar: Bool

    // MARK: - Initialization

    public init(
        viewModel: CardDeckViewModel,
        showsControlBar: Bool = false
    ) {
        self.viewModel = viewModel
        self.showsControlBar = showsControlBar
    }

    // MARK: - View Body

    public var body: some View {
        ZStack(alignment: .bottom) {
            let visible = viewModel.visibleCards

            if visible.isEmpty {
                EmptyStateView()
            } else {
                // 3-Card Sliding Window Stack (Reverse-enumerated so Card 0 renders on top)
                ZStack {
                    ForEach(Array(visible.enumerated().reversed()), id: \.element.id) { index, asset in
                        let isTop = (index == 0)
                        let p = viewModel.currentDragProgress

                        // Visual depth scaling & Y-offset interpolation conforming to 120Hz physics
                        let scale: Double = {
                            switch index {
                            case 0: return 1.0
                            case 1: return 0.94 + (0.06 * p)
                            case 2: return 0.88 + (0.06 * p)
                            default: return 0.82
                            }
                        }()

                        let offsetY: CGFloat = {
                            switch index {
                            case 0: return viewModel.activeDragOffset.height
                            case 1: return CGFloat(14.0 * (1.0 - p))
                            case 2: return CGFloat(26.0 - (12.0 * p))
                            default: return 36.0
                            }
                        }()

                        let offsetX: CGFloat = isTop ? viewModel.activeDragOffset.width : 0.0
                        let rotation: Double = isTop ? viewModel.currentRotationAngle : 0.0

                        PhotoCardView(
                            asset: asset,
                            dragOffset: isTop ? viewModel.activeDragOffset : .zero,
                            isTopCard: isTop
                        )
                        .scaleEffect(scale)
                        .offset(x: offsetX, y: offsetY)
                        .rotationEffect(.degrees(rotation))
                        .zIndex(Double(3 - index))
                        .gesture(
                            isTop ? DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.86, blendDuration: 0.05)) {
                                        #if os(iOS)
                                        viewModel.handleDragChanged(
                                            translation: gesture.translation,
                                            velocity: gesture.velocity
                                        )
                                        #else
                                        viewModel.handleDragChanged(
                                            translation: gesture.translation
                                        )
                                        #endif
                                    }
                                }
                                .onEnded { gesture in
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                                        #if os(iOS)
                                        _ = viewModel.handleDragEnded(
                                            translation: gesture.translation,
                                            velocity: gesture.velocity
                                        )
                                        #else
                                        _ = viewModel.handleDragEnded(
                                            translation: gesture.translation
                                        )
                                        #endif
                                    }
                                }
                            : nil
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Bottom Floating Control Bar (Undo, Trash, Keep buttons)
            if showsControlBar {
                bottomFloatingControlBar
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Floating Control Bar Component

    public var bottomFloatingControlBar: some View {
        HStack(spacing: 24) {
            // Undo Button (Restores last swiped card in LIFO order)
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    _ = viewModel.undoLastSwipe()
                }
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(viewModel.canUndo ? .primary : .secondary.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            .disabled(!viewModel.canUndo)
            .accessibilityLabel("Undo Last Action")

            // Trash Button (Programmatic Swipe Left / Stage Delete)
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                    _ = viewModel.swipeTopCard(direction: .stageDelete)
                }
            }) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.red)
                    .frame(width: 64, height: 64)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Circle())
            }
            .disabled(viewModel.isEmpty)
            .accessibilityLabel("Stage for Deletion")

            // Keep Button (Programmatic Swipe Right / Retain)
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                    _ = viewModel.swipeTopCard(direction: .retain)
                }
            }) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.green)
                    .frame(width: 64, height: 64)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Circle())
            }
            .disabled(viewModel.isEmpty)
            .accessibilityLabel("Keep Photo")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: Color(white: 0.0, opacity: 0.12), radius: 10, x: 0, y: 5)
    }
}
