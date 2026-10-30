import SwiftUI
import PoseKit
import ChoreoKit

/// Practice mode: the reference on the left, the mirrored front camera on the
/// right, and a rating for every half-second step.
struct PracticeView: View {
    let displaySize: CGSize
    @State private var model: PracticeModel
    @State private var showingResults = false

    init(url: URL, sequence: PoseSequence, displaySize: CGSize) {
        self.displaySize = displaySize
        _model = State(initialValue: PracticeModel(url: url, sequence: sequence, displaySize: displaySize))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                referencePane
                userPane
            }
            feedback
            tally
            SpeedPicker(rate: Bindable(model.player).rate)
            Button(model.isActive ? "Pause" : "Start",
                   systemImage: model.isActive ? "pause.fill" : "play.fill") {
                model.isActive ? model.pause() : model.start()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            Button("Results") {
                model.pause()
                showingResults = true
            }
            .disabled(model.results.isEmpty)
        }
        .sheet(isPresented: $showingResults) {
            PracticeResultsView(model: model)
        }
        .task { await model.camera.run() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            model.pause()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var referencePane: some View {
        ZStack {
            PlayerLayerView(player: model.player.player)
            TimelineView(.animation) { _ in
                if let pose = model.sequence.frame(at: model.player.player.currentTime().seconds), !pose.joints.isEmpty {
                    SkeletonView(frame: pose, color: .green)
                }
            }
        }
        .aspectRatio(displaySize, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var userPane: some View {
        ZStack {
            Color.white.opacity(0.08)
            switch model.camera.status {
            case .running:
                if let session = model.camera.camera?.session {
                    CameraPreview(session: session)
                }
                if let pose = model.camera.pose {
                    SkeletonView(frame: pose, color: model.liveRating?.color ?? .white)
                }
            case .starting:
                ProgressView()
            case .denied:
                message("Allow camera access for Dancing Studio in Settings to get scored.")
            case .unavailable:
                message("Practice needs the front camera. Run the app on an iPhone.")
            case .failed(let reason):
                message(reason)
            }
            if case .countdown(let n) = model.phase {
                Text("\(n)")
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText(countsDown: true))
                    .shadow(radius: 8)
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 12))
        .animation(.snappy, value: model.phase)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding()
    }

    private var feedback: some View {
        VStack(spacing: 4) {
            if let result = model.latest, model.phase != .ready {
                // A pop on each new step instead of a crossfade, which left
                // the old word showing through the new one.
                Text(result.rating.title)
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(result.rating.color)
                    .keyframeAnimator(initialValue: 1.0, trigger: model.results.count) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(1.15, duration: 0.08)
                        SpringKeyframe(1.0, duration: 0.2)
                    }
                Text(result.feedback?.message
                     ?? (result.rating == .perfect ? "Keep it up!" : "Keep your whole body in view."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Stand back so your whole body is in view, then tap Start and mirror the dancer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(height: 72)
    }

    private var tally: some View {
        HStack {
            ForEach(StepRating.allCases, id: \.self) { rating in
                VStack(spacing: 2) {
                    Text("\(model.count(of: rating))")
                        .font(.title3.bold())
                        .monospacedDigit()
                    Text(rating.title)
                        .font(.caption)
                        .foregroundStyle(rating.color)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct PracticeResultsView: View {
    let model: PracticeModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 4) {
                        Text("\(model.score)")
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                        Text("out of 100 over \(model.results.count) steps")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                Section("Steps") {
                    ForEach(StepRating.allCases, id: \.self) { rating in
                        LabeledContent(rating.title, value: "\(model.count(of: rating))")
                    }
                }
                if !model.commonFeedback.isEmpty {
                    Section("Work on") {
                        ForEach(model.commonFeedback, id: \.self) { Text($0.message) }
                    }
                }
                Section {
                    Button("Practice again") {
                        model.reset()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}

extension StepRating {
    var title: String {
        switch self {
        case .perfect: "Perfect"
        case .good: "Good"
        case .ok: "OK"
        case .miss: "Miss"
        }
    }

    var color: Color {
        switch self {
        case .perfect: .green
        case .good: .cyan
        case .ok: .yellow
        case .miss: .red
        }
    }

    /// Share of a perfect step this rating is worth in the overall score.
    var points: Double {
        switch self {
        case .perfect: 1
        case .good: 0.7
        case .ok: 0.4
        case .miss: 0
        }
    }
}

extension LimbFeedback {
    /// Phrased for the mirrored camera, where the left of the screen is the
    /// dancer's own left.
    var message: String {
        let side = switch side {
        case .left: "left "
        case .right: "right "
        case nil: ""
        }
        switch part {
        case .shoulders: return "Match the tilt of your shoulders"
        case .hips: return "Match the tilt of your hips"
        default: break
        }
        switch hint {
        case .raise, .lower:
            let name = switch part {
            case .upperArm: "arm"
            case .forearm: "hand"
            case .thigh: "knee"
            default: "foot"
            }
            return "\(hint == .raise ? "Raise" : "Lower") your \(side)\(name)"
        case .adjust:
            let name = switch part {
            case .upperArm: "upper arm"
            case .forearm: "forearm"
            case .thigh: "thigh"
            default: "lower leg"
            }
            return "Match the angle of your \(side)\(name)"
        }
    }
}
