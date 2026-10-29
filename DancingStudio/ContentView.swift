import SwiftUI
import PoseKit

/// Top-level tabs, one per area of the plan: solo learning, studio practice
/// and the personal move library. Each tab is a placeholder for now.
struct ContentView: View {
    var body: some View {
        TabView {
            LearnView()
                .tabItem { Label("Learn", systemImage: "figure.dance") }
            placeholder("Studio", detail: "Practice videos from your teachers will appear here.")
                .tabItem { Label("Studio", systemImage: "globe") }
            placeholder("Library", detail: "Moves you've learned will be collected here.")
                .tabItem { Label("Library", systemImage: "books.vertical") }
        }
    }

    private func placeholder(_ title: String, detail: String) -> some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: "hourglass", description: Text(detail))
                .navigationTitle(title)
        }
    }
}

private struct LearnView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                SkeletonView(frame: .samplePose)
                    .frame(height: 320)
                    .padding()
                    .background(.quaternary, in: .rect(cornerRadius: 16))
                Text("Import a dance video to turn it into a step-by-step tutorial.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Learn")
        }
    }
}

extension PoseFrame {
    /// An arms-up pose in Vision's normalized coordinates (origin bottom-left).
    static let samplePose = PoseFrame(time: 0, joints: [
        .nose: JointPoint(x: 0.5, y: 0.86),
        .neck: JointPoint(x: 0.5, y: 0.78),
        .leftShoulder: JointPoint(x: 0.42, y: 0.77), .rightShoulder: JointPoint(x: 0.58, y: 0.77),
        .leftElbow: JointPoint(x: 0.34, y: 0.86), .rightElbow: JointPoint(x: 0.66, y: 0.86),
        .leftWrist: JointPoint(x: 0.30, y: 0.97), .rightWrist: JointPoint(x: 0.70, y: 0.97),
        .root: JointPoint(x: 0.5, y: 0.50),
        .leftHip: JointPoint(x: 0.45, y: 0.50), .rightHip: JointPoint(x: 0.55, y: 0.50),
        .leftKnee: JointPoint(x: 0.42, y: 0.28), .rightKnee: JointPoint(x: 0.60, y: 0.28),
        .leftAnkle: JointPoint(x: 0.40, y: 0.05), .rightAnkle: JointPoint(x: 0.66, y: 0.05),
    ])
}

#Preview {
    ContentView()
}
