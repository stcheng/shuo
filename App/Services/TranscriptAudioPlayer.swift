import AVFoundation
import Foundation

@MainActor
final class TranscriptAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var onFinish: (() -> Void)?

    func play(
        _ url: URL,
        outputDeviceID: String? = nil,
        onFinish: @escaping () -> Void
    ) throws {
        stop(notify: false)

        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.currentDevice = outputDeviceID
        player.prepareToPlay()

        if !player.play(), outputDeviceID != nil {
            player.currentDevice = nil
            player.prepareToPlay()
            _ = player.play()
        }

        guard player.isPlaying else {
            throw TranscriptAudioPlayerError.failedToPlay
        }

        self.player = player
        self.onFinish = onFinish
    }

    func stop(notify: Bool = true) {
        guard let player else {
            return
        }

        player.stop()
        self.player = nil

        if notify {
            onFinish?()
        }
        onFinish = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.onFinish?()
            self.onFinish = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.player = nil
            self.onFinish?()
            self.onFinish = nil
        }
    }
}

enum TranscriptAudioPlayerError: LocalizedError {
    case failedToPlay

    var errorDescription: String? {
        switch self {
        case .failedToPlay:
            return "Audio playback could not be started."
        }
    }
}
