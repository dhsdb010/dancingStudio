import AVFoundation
import SwiftUI
import PoseKit
import ChoreoKit

/// The step-by-step tutorial: loops the whole routine or one 8-count at a
/// time, with the extracted skeleton and the dancer's count on top, and
/// slow-motion speeds for learning the moves.
struct RoutinePlayerView: View {
    let url: URL
    let analysis: RoutineAnalysis
    let displaySize: CGSize
    @State private var model: RoutinePlayerModel
    /// Nil plays the whole routine.
    @State private var section: RoutineSection?

    init(url: URL, analysis: RoutineAnalysis, displaySize: CGSize) {
        self.url = url
        self.analysis = analysis
        self.displaySize = displaySize
        _model = State(initialValue: RoutinePlayerModel(url: url, start: analysis.sequence.start, end: analysis.sequence.end))
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topLeading) {
                PlayerLayerView(player: model.player)
                TimelineView(.animation) { _ in
                    if let pose = analysis.sequence.frame(at: model.player.currentTime().seconds), !pose.joints.isEmpty {
                        SkeletonView(frame: pose, color: .green)
                    }
                }
                if let beats = analysis.beats {
                    CountBadge(beats: beats, player: model.player)
                        .padding(8)
                }
            }
            .aspectRatio(displaySize, contentMode: .fit)
            .background(.black)
            .clipShape(.rect(cornerRadius: 12))

            sectionPicker

            SpeedPicker(rate: $model.rate)

            HStack {
                Button(model.isPlaying ? "Pause" : "Play",
                       systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                    model.togglePlayback()
                }
                .buttonStyle(.bordered)
                NavigationLink {
                    PracticeView(url: url, sequence: practiceSequence, beats: analysis.beats, displaySize: displaySize)
                } label: {
                    Label(section.map { "Practice \(title(for: $0))" } ?? "Practice all",
                          systemImage: "figure.dance")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onAppear { model.play() }
        .onDisappear { model.pause() }
        .onChange(of: section) { _, section in
            model.setRange(start: section?.start ?? analysis.sequence.start,
                           end: section?.end ?? analysis.sequence.end)
        }
    }

    private var sectionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip("All", selected: section == nil) { section = nil }
                    ForEach(analysis.sections) { item in
                        chip("\(item.index + 1)", selected: section == item) { section = item }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .frame(minWidth: 28)
            .buttonStyle(.bordered)
            .tint(selected ? .accentColor : .secondary)
            .buttonBorderShape(.capsule)
    }

    private var summary: String {
        let count = analysis.sections.count
        guard let beats = analysis.beats else {
            return "No steady beat found · \(count) part\(count == 1 ? "" : "s")"
        }
        let bpm = "\(Int(beats.bpm.rounded())) BPM"
        guard analysis.sectionsArePhrases else {
            return "\(bpm) · shorter than one 8-count · \(count) part\(count == 1 ? "" : "s")"
        }
        return "\(bpm) · \(count) eight-count\(count == 1 ? "" : "s")"
    }

    private func title(for section: RoutineSection) -> String {
        analysis.sectionsArePhrases ? "8-count \(section.index + 1)" : "part \(section.index + 1)"
    }

    private var practiceSequence: PoseSequence {
        guard let section else { return analysis.sequence }
        return analysis.sequence.slice(from: section.start, to: section.end)
    }
}

/// The dancer's count, 1 to 8, following the music.
struct CountBadge: View {
    let beats: BeatGrid
    let player: AVPlayer

    var body: some View {
        TimelineView(.animation) { _ in
            if let count = beats.count(at: player.currentTime().seconds) {
                Text("\(count)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(count == 1 ? .yellow : .white)
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.55), in: .circle)
                    .accessibilityLabel("Count \(count)")
            }
        }
    }
}

/// Slow-motion speeds for learning the moves.
struct SpeedPicker: View {
    @Binding var rate: Float

    private static let speeds: [Float] = [0.25, 0.5, 0.75, 1]

    var body: some View {
        Picker("Speed", selection: $rate) {
            ForEach(Self.speeds, id: \.self) { speed in
                Text(speed == 1 ? "1×" : "\(speed.formatted())×").tag(speed)
            }
        }
        .pickerStyle(.segmented)
    }
}

@MainActor @Observable
final class RoutinePlayerModel {
    let player = AVQueuePlayer()
    private let url: URL
    private var looper: AVPlayerLooper
    private(set) var isPlaying = false

    /// Playback speed; pitch is preserved so the music stays recognizable.
    var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if isPlaying { player.rate = rate }
        }
    }

    init(url: URL, start: TimeInterval, end: TimeInterval) {
        self.url = url
        looper = Self.makeLooper(player: player, url: url, start: start, end: end)
    }

    /// Loops `start` to `end` instead, e.g. a single 8-count.
    func setRange(start: TimeInterval, end: TimeInterval) {
        looper.disableLooping()
        player.removeAllItems()
        looper = Self.makeLooper(player: player, url: url, start: start, end: end)
        if isPlaying { play() }
    }

    private static func makeLooper(player: AVQueuePlayer, url: URL, start: TimeInterval, end: TimeInterval) -> AVPlayerLooper {
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        return AVPlayerLooper(player: player, templateItem: item, timeRange: range)
    }

    func play() {
        // Play the music even with the silent switch on.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
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

    func seek(to time: TimeInterval) {
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

struct PlayerLayerView: UIViewRepresentable {
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
