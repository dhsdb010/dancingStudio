import AVFoundation
import SwiftUI
import PoseKit

/// Trim an imported video to the part to learn, then extract its poses and
/// find its beat. Shows the step-by-step player when analysis finishes.
struct PrepareRoutineView: View {
    let video: PickedVideo

    @State private var duration: TimeInterval?
    @State private var displaySize = CGSize(width: 9, height: 16)
    @State private var start: TimeInterval = 0
    @State private var end: TimeInterval = 0
    @State private var phase = Phase.trimming

    private enum Phase {
        case trimming
        case analyzing(progress: Double)
        case findingBeat
        case ready(RoutineAnalysis)
        case failed(String)
    }

    var body: some View {
        Group {
            switch phase {
            case .ready(let analysis):
                RoutinePlayerView(url: video.url, analysis: analysis, displaySize: displaySize)
            case .analyzing(let progress):
                VStack(spacing: 16) {
                    ProgressView(value: progress)
                    Text("Analyzing moves… \(Int(progress * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(32)
            case .findingBeat:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Finding the beat…")
                        .foregroundStyle(.secondary)
                }
            case .failed(let reason):
                ContentUnavailableView("Couldn't analyze this video", systemImage: "exclamationmark.triangle",
                                       description: Text(reason))
            case .trimming:
                trimForm
            }
        }
        .navigationTitle("New routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await loadVideoInfo() }
    }

    @ViewBuilder
    private var trimForm: some View {
        if let duration {
            Form {
                Section {
                    LabeledContent("Start", value: Self.format(start))
                    Slider(value: $start, in: 0...duration)
                        .onChange(of: start) { if end < start { end = start } }
                    LabeledContent("End", value: Self.format(end))
                    Slider(value: $end, in: 0...duration)
                        .onChange(of: end) { if start > end { start = end } }
                } header: {
                    Text("Part to learn")
                } footer: {
                    Text("\(Self.format(end - start)) selected. Shorter clips analyze faster.")
                }
                Section {
                    Button("Analyze moves") { Task { await analyze() } }
                        .disabled(end - start < 1)
                }
            }
        } else {
            ProgressView()
        }
    }

    private func loadVideoInfo() async {
        let asset = AVURLAsset(url: video.url)
        do {
            let seconds = try await asset.load(.duration).seconds
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
                let upright = size.applying(transform)
                displaySize = CGSize(width: abs(upright.width), height: abs(upright.height))
            }
            duration = seconds
            end = seconds
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func analyze() async {
        phase = .analyzing(progress: 0)
        do {
            let sequence = try await VideoPoseExtractor().extract(from: video.url, start: start, end: end) { value in
                Task { @MainActor in
                    if case .analyzing = phase { phase = .analyzing(progress: value) }
                }
            }
            phase = .findingBeat
            phase = .ready(await RoutineAnalysis.make(url: video.url, sequence: sequence))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
