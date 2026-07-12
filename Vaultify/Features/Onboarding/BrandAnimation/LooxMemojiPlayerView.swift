//
//  LooxMemojiPlayerView.swift
//  Vaultify
//
//  Loops a transparent Memoji clip (HEVC with alpha) on the cluster's
//  identity disc. Each clip loops on its own clock, independent of the
//  master animation timeline — matching how the iCloud landing page
//  keeps its avatars idling.
//

import AVFoundation
import SwiftUI

struct LooxMemojiPlayerView: UIViewRepresentable {
    /// Bundle resource name of a .mov with an alpha channel.
    let resourceName: String
    /// Increments every time this Memoji's scene comes around in the master
    /// loop; a change rewinds the clip so it always opens the scene from
    /// its first frame.
    let restartKey: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> LooxPlayerLayerView {
        let view = LooxPlayerLayerView()
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
    private var looper: AVPlayerLooper?

    /// Rewinds to the first frame, e.g. when the owning scene re-enters.
    func restart() {
        playerLayer.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    func configure(url: URL) {
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))

        // A nil background keeps the alpha channel compositing over SwiftUI.
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = nil

        backgroundColor = .clear
        isUserInteractionEnabled = false
        player.play()
    }
}
