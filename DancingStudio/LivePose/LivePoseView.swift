import AVFoundation
import SwiftUI
import PoseKit

/// Front camera with the detected skeleton drawn on top and an fps readout,
/// for checking how well live pose tracking runs on a real iPhone.
struct LivePoseView: View {
    @State private var model = LivePoseModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .top) {
            if model.status == .running { stats }
        }
        .navigationTitle("Live tracking")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await model.run() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .starting:
            ProgressView()
        case .running:
            if let session = model.camera?.session {
                // 720×1280 portrait frames; both layers share this box so
                // Vision's normalized coordinates land on the right pixels.
                ZStack {
                    CameraPreview(session: session)
                    if let pose = model.pose {
                        SkeletonView(frame: pose, color: .green)
                    }
                }
                .aspectRatio(9 / 16, contentMode: .fit)
            }
        case .denied:
            ContentUnavailableView("Camera access is off", systemImage: "video.slash",
                                   description: Text("Allow camera access for Dancing Studio in Settings to track your moves."))
        case .unavailable:
            ContentUnavailableView("No camera", systemImage: "video.slash",
                                   description: Text("Live tracking needs a front camera. Run the app on an iPhone."))
        case .failed(let reason):
            ContentUnavailableView("Camera error", systemImage: "exclamationmark.triangle",
                                   description: Text(reason))
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            Text("\(Int(model.fps.rounded())) fps")
            Text("\(Int(model.detectionMs.rounded())) ms")
            if model.pose == nil {
                Text("No dancer in frame")
            }
        }
        .font(.footnote.weight(.semibold))
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: .capsule)
        .padding(.top, 8)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        if let connection = view.previewLayer.connection,
           connection.isVideoRotationAngleSupported(PoseCamera.rotationAngle) {
            connection.videoRotationAngle = PoseCamera.rotationAngle
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
