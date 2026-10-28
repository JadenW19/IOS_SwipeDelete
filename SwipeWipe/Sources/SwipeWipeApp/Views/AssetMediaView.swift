//
//  AssetMediaView.swift
//  SwipeWipeApp
//
//  Loads and renders the real photo (or video poster + muted looping playback) for a card.
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

/// UIKit-backed video layer (no hit testing, so the card's drag gesture keeps working).
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = .resizeAspectFill
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

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)

            if let image {
                Image(decorative: image, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
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
                }
                if player == nil {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(radius: 6)
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
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let player, let item = note.object as? AVPlayerItem, item === player.currentItem else { return }
            player.seek(to: .zero)
            player.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

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
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .moviePlayback, options: [.mixWithOthers])
        let newPlayer = AVPlayer(playerItem: box.value)
        newPlayer.isMuted = true
        newPlayer.play()
        player = newPlayer
    }
}

#else

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
