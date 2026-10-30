import AVFoundation
import SwiftData
import SwiftUI
import PoseKit
import ChoreoKit

/// Trim an imported video to the part to learn with a Photos-style trimmer
/// (the start becomes count 1), then extract its poses and show the
/// step-by-step player. The dancer chooses whether to save it to the library,
/// under a name of their own ("Dance 3" by default), and is asked before
/// leaving an unsaved one.
struct PrepareRoutineView: View {
    let video: PickedVideo

    @State private var duration: TimeInterval?
    @State private var displaySize = CGSize(width: 9, height: 16)
    @State private var start: TimeInterval = 0
    @State private var end: TimeInterval = 0
    @State private var phase = Phase.trimming
    @State private var preview: TrimPreviewModel?
    @State private var thumbnails: [CGImage] = []
    /// The beat across the whole video, found while trimming.
    @State private var fullBeats: BeatGrid?
    @State private var findingBeats = true
    /// "Saved to Library", or why saving failed; shown briefly over the player.
    @State private var saveMessage: String?
    /// The name it was saved under; nil while unsaved.
    @State private var savedTitle: String?
    @State private var showingNamePrompt = false
    @State private var nameDraft = ""
    @State private var showingLeavePrompt = false
    /// Leave once the save from the leave prompt finishes.
    @State private var leaveAfterSaving = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var savedRoutines: [SavedRoutine]

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
        // At the top, clear of the playback and practice buttons.
        .overlay(alignment: .top) {
            if let saveMessage {
                Text(saveMessage)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: saveMessage)
        .navigationTitle(savedTitle ?? "New routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        // A custom back button so leaving an unsaved dance can ask first.
        // (Hiding the system one also stops the swipe-back gesture.)
        .navigationBarBackButtonHidden(isUnsaved)
        .toolbar {
            if isUnsaved {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.left") { showingLeavePrompt = true }
                }
            }
            if isReady {
                ToolbarItem(placement: .topBarTrailing) {
                    if savedTitle == nil {
                        Button("Save") { promptForName() }
                            .fontWeight(.semibold)
                    } else {
                        Label("Saved", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .alert("Save dance", isPresented: $showingNamePrompt) {
            TextField("Name", text: $nameDraft)
            Button("Save") { Task { await save() } }
            Button("Cancel", role: .cancel) { leaveAfterSaving = false }
        } message: {
            Text("Name it to find it later in your Library.")
        }
        .confirmationDialog("Save this dance before leaving?", isPresented: $showingLeavePrompt,
                            titleVisibility: .visible) {
            Button("Save…") {
                leaveAfterSaving = true
                promptForName()
            }
            Button("Don't Save", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If you don't save it, you'll need to import and analyze the video again.")
        }
        .task { await loadVideoInfo() }
    }

    private var isReady: Bool {
        if case .ready = phase { true } else { false }
    }

    private var isUnsaved: Bool { isReady && savedTitle == nil }

    /// "Dance N", one past the highest number already used.
    private var defaultName: String {
        let used = savedRoutines.compactMap { routine -> Int? in
            guard routine.title.hasPrefix("Dance ") else { return nil }
            return Int(routine.title.dropFirst("Dance ".count))
        }
        return "Dance \((used.max() ?? 0) + 1)"
    }

    private func promptForName() {
        nameDraft = defaultName
        showingNamePrompt = true
    }

    @ViewBuilder
    private var trimForm: some View {
        if let duration, let preview {
            VStack(spacing: 16) {
                ZStack(alignment: .topLeading) {
                    PlayerLayerView(player: preview.player)
                    if let grid = trimmedBeats {
                        CountBadge(beats: grid, player: preview.player)
                            .padding(8)
                    }
                }
                .aspectRatio(displaySize, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    if !preview.isPlaying {
                        Image(systemName: "play.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(.black.opacity(0.45), in: .circle)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(.rect)
                .onTapGesture { preview.togglePlayback() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(preview.isPlaying ? "Pause preview" : "Play selection")

                ClipTrimmer(duration: duration, thumbnails: thumbnails, beats: fullBeats?.beats ?? [],
                            start: $start, end: $end, playhead: preview.currentTime,
                            onScrub: { preview.scrub(to: $0) })

                HStack(alignment: .bottom) {
                    endpoint("Start", isStart: true)
                    Spacer()
                    VStack(spacing: 2) {
                        Text("Length").font(.caption).foregroundStyle(.secondary)
                        Text(Self.format(end - start, precise: true)).monospacedDigit()
                    }
                    Spacer()
                    endpoint("End", isStart: false)
                }

                Text(trimHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 36)

                Button("Analyze moves") {
                    preview.pause()
                    Task { await analyze() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(end - start < 1)
            }
            .padding()
            .onChange(of: start) { preview.range = start...end }
            .onChange(of: end) { preview.range = start...end }
            .onDisappear { preview.pause() }
        } else {
            ProgressView()
        }
    }

    private func endpoint(_ label: String, isStart: Bool) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Button("Earlier", systemImage: "chevron.left") { nudge(isStart: isStart, by: -1) }
                Text(Self.format(isStart ? start : end, precise: true))
                    .monospacedDigit()
                    .frame(minWidth: 56)
                Button("Later", systemImage: "chevron.right") { nudge(isStart: isStart, by: 1) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
        }
    }

    private var trimHint: String {
        if findingBeats { return "Finding the beat…" }
        if fullBeats != nil {
            return "Drag the yellow handles. The start snaps to the beat and becomes count 1. Tap the video to preview."
        }
        return "No steady beat found, so the routine will be split into equal parts. Tap the video to preview."
    }

    /// The beats of the current selection, counting 1 from the start.
    private var trimmedBeats: BeatGrid? {
        fullBeats?.trimmed(from: start, to: end)
    }

    /// Moves the start or end by one beat, or by a tenth of a second when
    /// there's no beat, and shows that frame.
    private func nudge(isStart: Bool, by step: Int) {
        guard let duration else { return }
        let current = isStart ? start : end
        var target = current + Double(step) * 0.1
        if let beats = fullBeats?.beats, !beats.isEmpty {
            let next = step > 0 ? beats.first { $0 > current + 0.01 } : beats.last { $0 < current - 0.01 }
            target = next ?? (step > 0 ? duration : 0)
        }
        if isStart {
            start = min(max(0, target), end - 1)
            preview?.scrub(to: start)
        } else {
            end = max(min(duration, target), start + 1)
            preview?.scrub(to: end)
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
            let preview = TrimPreviewModel(url: video.url)
            preview.range = 0...seconds
            self.preview = preview
            duration = seconds
            end = seconds
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        // Thumbnails and the beat load side by side after the trimmer shows.
        async let strip = Self.thumbnails(of: video.url, duration: duration ?? 0, count: 10)
        async let beats = Self.findBeats(in: video.url, duration: duration ?? 0)
        thumbnails = await strip
        fullBeats = await beats
        findingBeats = false
        // Start on a beat from the outset, so the first count is a "1".
        if start == 0, let first = fullBeats?.beats.first, first < 1 {
            start = first
        }
    }

    private nonisolated static func thumbnails(of url: URL, duration: TimeInterval, count: Int) async -> [CGImage] {
        guard duration > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        let times = (0..<count).map { CMTime(seconds: duration * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
        var images: [CGImage] = []
        for await result in generator.images(for: times) {
            if let image = try? result.image { images.append(image) }
        }
        return images
    }

    private nonisolated static func findBeats(in url: URL, duration: TimeInterval) async -> BeatGrid? {
        guard let samples = (try? await AudioLoader.samples(from: url, start: 0, end: duration)) ?? nil else { return nil }
        return BeatTracker().track(samples: samples, sampleRate: AudioLoader.sampleRate)
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
            let analysis = await RoutineAnalysis.make(url: video.url, sequence: sequence, beats: fullBeats)
            phase = .ready(analysis)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func save() async {
        guard case .ready(let analysis) = phase else { return }
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.isEmpty ? defaultName : name
        do {
            try await RoutineStore.save(video: video.url, analysis: analysis, displaySize: displaySize,
                                        title: title, in: modelContext)
            savedTitle = title
            if leaveAfterSaving {
                dismiss()
                return
            }
            saveMessage = "Saved to Library as \u{201C}\(title)\u{201D}"
        } catch {
            leaveAfterSaving = false
            saveMessage = "Couldn't save: \(error.localizedDescription)"
        }
        try? await Task.sleep(for: .seconds(2.5))
        saveMessage = nil
    }

    /// "1:05", or "1:05.3" when `precise`.
    static func format(_ seconds: TimeInterval, precise: Bool = false) -> String {
        guard precise else {
            let total = Int(seconds.rounded(.down))
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        let tenths = Int((seconds * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
    }
}
