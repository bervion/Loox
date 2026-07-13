//
//  LooxMemojiPlayerView.swift
//  Vaultify
//
//  Loops a transparent Memoji clip (HEVC with alpha) on the cluster's
//  identity disc. Each clip loops on its own clock, independent of the
//  master animation timeline — matching how the iCloud landing page
//  keeps its avatars idling.
//
//  Robustness:
//  - A static poster frame sits behind the video, so the face still shows
//    if the video can't render (the Simulator decodes HEVC-with-alpha
//    unreliably; real devices are fine). The video, when it plays, covers
//    the identical poster seamlessly.
//  - The player runs a video-ONLY composition: the clips carry a silent
//    audio track that would otherwise make AVPlayer open an audio queue and
//    spam the Simulator's audio HAL. Dropping it also means no sound.
//

import AVFoundation
import SwiftUI
import UIKit

struct LooxMemojiPlayerView: UIViewRepresentable {
    /// Bundle resource name of a .mov with an alpha channel. A matching
    /// "<name>-poster" image (asset catalog) is used as the static fallback.
    let resourceName: String
    /// Increments every time this Memoji's scene comes around in the master
    /// loop; a change rewinds the clip so it always opens the scene from
    /// its first frame.
    let restartKey: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> LooxPlayerLayerView {
        let view = LooxPlayerLayerView()
        view.setPoster(UIImage(named: "\(resourceName)-poster"))
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "mov") {
            view.configure(url: url)
        }
        context.coordinator.lastKey = restartKey
        return view
    }

    func updateUIView(_ uiView: LooxPlayerLayerView, context: Context) {
        if context.coordinator.lastKey != restartKey {
            context.coordinator.lastKey = restartKey
            uiView.restart()
        }
    }

    final class Coordinator {
        var lastKey: Int = .min
    }
}

final class LooxPlayerLayerView: UIView {
    /// Static fallback frame, behind the video.
    private let posterView = UIImageView()
    /// Video layer, above the poster.
    private let playerLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        posterView.contentMode = .scaleAspectFill
        posterView.clipsToBounds = true
        posterView.frame = bounds
        posterView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(posterView)

        // Added after the poster's layer, so the video composites on top.
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = nil
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func setPoster(_ image: UIImage?) { posterView.image = image }

    /// Rewinds to the first frame, e.g. when the owning scene re-enters.
    func restart() {
        playerLayer.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func configure(url: URL) {
        let asset = AVURLAsset(url: url)
        // Build a video-only item so AVPlayer never opens an audio queue for the
        // clip's silent AAC track. Falls back to the raw asset if that fails.
        Task { @MainActor [weak self] in
            let item: AVPlayerItem
            if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first,
               let duration = try? await asset.load(.duration) {
                let composition = AVMutableComposition()
                let track = composition.addMutableTrack(withMediaType: .video,
                                                        preferredTrackID: kCMPersistentTrackID_Invalid)
                try? track?.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                            of: videoTrack, at: .zero)
                item = AVPlayerItem(asset: composition)
            } else {
                item = AVPlayerItem(url: url)
            }
            self?.startLooping(with: item)
        }
    }

    private func startLooping(with item: AVPlayerItem) {
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        // A nil player-layer background keeps the alpha channel compositing.
        looper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer.player = player
        player.play()
    }
}
