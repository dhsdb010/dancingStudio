import AVFoundation
import Observation
import PoseKit

/// Drives the live tracking screen: asks for camera access, runs `PoseCamera`
/// and keeps the latest pose plus throughput stats for the spike.
@MainActor @Observable
final class LivePoseModel {
    enum Status: Equatable {
        case starting, running, denied, unavailable
        case failed(String)
    }

    private(set) var status: Status = .starting
    private(set) var pose: PoseFrame?
    /// Frames Vision finished per second, averaged over about a second.
    private(set) var fps: Double = 0
    /// Vision time for the latest frame, in milliseconds.
    private(set) var detectionMs: Double = 0
    private(set) var camera: PoseCamera?
    /// Called with every camera result, including nil when nobody is tracked.
    var onSample: ((PoseFrame?) -> Void)?

    /// Runs until the calling task is cancelled, e.g. when the view disappears.
    func run() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            status = .denied
            return
        }

        let camera = PoseCamera()
        do {
            try await camera.start()
        } catch PoseCamera.CameraError.unavailable {
            status = .unavailable
            return
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        self.camera = camera
        status = .running

        var windowStart = Date.now
        var frames = 0
        for await sample in camera.samples {
            pose = sample.pose
            onSample?(sample.pose)
            detectionMs = sample.detectionTime * 1000
            frames += 1
            let elapsed = Date.now.timeIntervalSince(windowStart)
            if elapsed >= 1 {
                fps = Double(frames) / elapsed
                frames = 0
                windowStart = .now
            }
        }

        camera.stop()
        self.camera = nil
    }
}
