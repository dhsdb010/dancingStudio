import AVFoundation
import SwiftUI
import PoseKit

/// Loops the trimmed part of the video with the extracted skeleton on top,
/// with slow-motion speeds for learning the moves.
struct RoutinePlayerView: View {
    let sequence: PoseSequence
    let displaySize: CGSize
    @State private var model: RoutinePlayerModel

    init(url: URL, sequence: PoseSequence, displaySize: CGSize) {
        self.sequence = sequence
        self.displaySize = displaySize
        _model = State(initialValue: RoutinePlayerModel(url: url, start: sequence.start, end: sequence.end))
    }

    private static let speeds: [Float] = [0.25, 0.5, 0.75, 1]

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                PlayerLayerView(player: model.player)
                TimelineView(.animation) { _ in
                    if let pose = sequence.frame(at: model.player.currentTime().seconds), !pose.joints.isEmpty {
                        SkeletonView(frame: pose, color: .green)
                    }
                }
            }
            .aspectRatio(displaySize, contentMode: .fit)
            .background(.black)
            .clipShape(.rect(cornerRadius: 12))

            Picker("Speed", selection: $model.rate) {
                ForEach(Self.speeds, id: \.self) { speed in
                    Text(speed == 1 ? "1×" : "\(speed.formatted())×").tag(speed)
                }
            }
            .pickerStyle(.segmented)

            Button(model.isPlaying ? "Pause" : "Play",
                   systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                model.togglePlayback()
            }
            .buttonStyle(.borderedProminent)

            Text("\(detectedPercent)% of frames have a detected dancer")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { model.play() }
        .onDisappear { model.pause() }
    }

    private var detectedPercent: Int {
        guard !sequence.frames.isEmpty else { return 0 }
        let detected = sequence.frames.filter { !$0.joints.isEmpty }.count
        return detected * 100 / sequence.frames.count
    }
}

@MainActor @Observable
final class RoutinePlayerModel {
    let player = AVQueuePlayer()
    private let looper: AVPlayerLooper
    private(set) var isPlaying = false

    /// Playback speed; pitch is preserved so the music stays recognizable.
    var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if isPlaying { player.rate = rate }
        }
    }

    init(url: URL, start: TimeInterval, end: TimeInterval) {
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        looper = AVPlayerLooper(player: player, templateItem: item, timeRange: range)
    }

    func play() {
        player.rate = rate
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: LayerView, context: Context) {}

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
