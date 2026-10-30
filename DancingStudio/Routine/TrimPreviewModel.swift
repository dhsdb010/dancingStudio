import AVFoundation
import Observation

/// Plays the video while trimming: jumps to the frame under a dragged handle,
/// and loops the selected range when playing.
@MainActor @Observable
final class TrimPreviewModel {
    let player: AVPlayer
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    /// The selection to loop.
    var range: ClosedRange<TimeInterval> = 0...0
    private var observer: Any?

    init(url: URL) {
        player = AVPlayer(url: url)
        player.currentItem?.audioTimePitchAlgorithm = .timeDomain
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            // Start from the beginning of the selection unless already inside it.
            if currentTime < range.lowerBound || currentTime >= range.upperBound - 0.05 {
                seek(to: range.lowerBound)
            }
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    /// Shows the frame at `time`, pausing playback.
    func scrub(to time: TimeInterval) {
        pause()
        seek(to: time)
    }

    private func seek(to time: TimeInterval) {
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    private func tick(_ time: TimeInterval) {
        guard isPlaying else { return }
        currentTime = time
        if time >= range.upperBound { seek(to: range.lowerBound) }
    }
}
