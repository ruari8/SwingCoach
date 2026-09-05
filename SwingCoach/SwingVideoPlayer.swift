import AVKit
import SwiftUI

/// Video presentation for screens that provide their own playback controls.
struct SwingVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        // SwingCoach owns the gestures; Live Text and Visual Look Up are unused.
        // Disabling hit testing alone still lets AVKit analyse paused frames.
        controller.allowsVideoFrameAnalysis = false
        controller.videoGravity = .resizeAspect
        controller.player = player
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player = nil
    }
}
