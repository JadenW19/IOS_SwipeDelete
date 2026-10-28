//
//  AssetMediaView.swift
//  SwipeWipeApp
//
//  Loads and renders the real photo or video (with audio, play/pause, mute toggle,
//  and interactive scrubbing bar) for a swipe card.
//

import SwiftUI
import SwipeWipeCore
import CoreGraphics

#if canImport(UIKit) && canImport(Photos)
import UIKit
import Photos
import AVFoundation

// MARK: - Environment injection of the photo provider

private struct PhotoProviderKey: EnvironmentKey {
    static let defaultValue: (any PhotoLibraryProviding)? = nil
}

extension EnvironmentValues {
    var photoProvider: (any PhotoLibraryProviding)? {
        get { self[PhotoProviderKey.self] }
        set { self[PhotoProviderKey.self] = newValue }
    }
}

// MARK: - Helpers

private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

private func loadPlayerItem(localIdentifier: String) async -> UncheckedBox<AVPlayerItem>? {
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
    guard let asset = assets.firstObject else { return nil }

    let options = PHVideoRequestOptions()
    options.isNetworkAccessAllowed = true
    options.deliveryMode = .automatic

    let once = OnceFlag()
    return await withCheckedContinuation { (continuation: CheckedContinuation<UncheckedBox<AVPlayerItem>?, Never>) in
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
            guard once.fire() else { return }
            continuation.resume(returning: item.map { UncheckedBox(value: $0) })
        }
    }
}

/// UIKit-backed video layer (no hit testing on the layer itself so card swipes still work).
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: LayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

// MARK: - Media view

struct AssetMediaView: View {
    let asset: PhotoAssetModel
    let isTopCard: Bool
    let size: CGSize

    @Environment(\.photoProvider) private var provider
    @State private var image: CGImage?
    @State private var player: AVPlayer?
    @State private var didFail = false

    // Video playback & scrubbing state
    @State private var isPlaying: Bool = true
    @State private var isMuted: Bool = false
    @State private var currentTime: Double = 0.0
    @State private var totalDuration: Double = 1.0
    @State private var isScrubbing: Bool = false

    private let progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)

            if let image {
                // Soft ambient backdrop filling any letterbox/pillarbox margins
                Image(decorative: image, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .blur(radius: 26)
                    .overlay(Color.black.opacity(0.35))
                    .clipped()

                // Full uncropped image fit cleanly inside the card bounds
                Image(decorative: image, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
            } else {
                Image(systemName: asset.mediaType == .video ? "video.fill" : "photo.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(Color.accentColor.opacity(0.8))
                    .opacity(didFail ? 0.4 : 1.0)
            }

            if asset.mediaType == .video {
                if isTopCard, let player {
                    PlayerLayerView(player: player)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .allowsHitTesting(false)

                    // Interactive video controls overlay (scrubber + play/pause + mute)
                    videoControlsOverlay(player: player)
                } else if player == nil {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(radius: 6)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: asset.id) {
            await loadImage()
        }
        .task(id: "\(asset.id)-\(isTopCard)") {
            await updatePlayback()
        }
        .onReceive(progressTimer) { _ in
            guard isTopCard, !isScrubbing, let player else { return }
            let sec = player.currentTime().seconds
            if sec.isFinite && sec >= 0 {
                currentTime = sec
            }
            if let itemDuration = player.currentItem?.duration.seconds,
               itemDuration.isFinite && itemDuration > 0 {
                totalDuration = itemDuration
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let player, let item = note.object as? AVPlayerItem, item === player.currentItem else { return }
            player.seek(to: .zero)
            if isPlaying {
                player.play()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    // MARK: - Video Scrubber & Audio Controls

    @ViewBuilder
    private func videoControlsOverlay(player: AVPlayer) -> some View {
        VStack {
            Spacer()

            HStack(spacing: 10) {
                // Play / Pause button
                Button(action: {
                    if isPlaying {
                        player.pause()
                        isPlaying = false
                    } else {
                        player.play()
                        isPlaying = true
                    }
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Interactive Scrubber Track
                GeometryReader { geo in
                    let width = max(1.0, geo.size.width)
                    let progress = min(max(currentTime / max(totalDuration, 0.1), 0.0), 1.0)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 5)

                        Capsule()
                            .fill(Color.white)
                            .frame(width: width * CGFloat(progress), height: 5)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                            .offset(x: max(0, min(width - 14, width * CGFloat(progress) - 7)))
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isScrubbing = true
                                let fraction = min(max(Double(value.location.x / width), 0.0), 1.0)
                                let targetSeconds = fraction * max(totalDuration, 0.1)
                                currentTime = targetSeconds
                                let cmTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
                                player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                            }
                            .onEnded { _ in
                                isScrubbing = false
                                if isPlaying {
                                    player.play()
                                }
                            }
                    )
                }
                .frame(height: 28)

                // Elapsed / Total Timestamp
                Text("\(formatTime(currentTime))/\(formatTime(totalDuration))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: true, vertical: false)

                // Mute / Unmute button
                Button(action: {
                    isMuted.toggle()
                    player.isMuted = isMuted
                }) {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
            .padding(.horizontal, 16)
            // Sit cleanly above the bottom metadata rows (date + size badges)
            .padding(.bottom, 86)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Data Loading

    private func loadImage() async {
        guard let provider else { didFail = true; return }
        let scale = UIScreen.main.scale
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        do {
            if let cg = try await provider.loadThumbnail(for: asset.localIdentifier, targetSize: target) {
                image = cg
                didFail = false
            } else {
                didFail = true
            }
        } catch {
            didFail = true
        }
    }

    private func updatePlayback() async {
        guard asset.mediaType == .video else { return }
        guard isTopCard else {
            player?.pause()
            player = nil
            return
        }
        guard player == nil, let box = await loadPlayerItem(localIdentifier: asset.localIdentifier) else { return }
        // Configure audio session for video playback with sound
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let newPlayer = AVPlayer(playerItem: box.value)
        newPlayer.isMuted = isMuted
        totalDuration = max(asset.duration, 1.0)
        currentTime = 0.0
        isPlaying = true
        newPlayer.play()
        player = newPlayer
    }
}

// MARK: - Small thumbnail (review queue grid, etc.)

struct AssetThumbnailView: View {
    let localIdentifier: String
    let isVideo: Bool

    @Environment(\.photoProvider) private var provider
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.secondarySystemBackground)

                if let image {
                    Image(decorative: image, scale: 1.0, orientation: .up)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Image(systemName: isVideo ? "video.fill" : "photo.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.8))
                }

                if isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(radius: 4)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: localIdentifier) {
                guard let provider else { return }
                let scale = UIScreen.main.scale
                let target = CGSize(width: 200 * scale, height: 240 * scale)
                image = try? await provider.loadThumbnail(for: localIdentifier, targetSize: target)
            }
        }
    }
}

#else

struct AssetThumbnailView: View {
    let localIdentifier: String
    let isVideo: Bool

    var body: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: isVideo ? "video.fill" : "photo.fill")
        }
    }
}

// Non-iOS fallback (macOS builds of the package): placeholder only.
extension EnvironmentValues {
    var photoProvider: (any PhotoLibraryProviding)? {
        get { nil }
        set { }
    }
}

struct AssetMediaView: View {
    let asset: PhotoAssetModel
    let isTopCard: Bool
    let size: CGSize

    var body: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: asset.mediaType == .video ? "video.fill" : "photo.fill")
                .font(.system(size: 64, weight: .light))
        }
        .frame(width: size.width, height: size.height)
    }
}

#endif
