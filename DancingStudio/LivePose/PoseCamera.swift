import AVFoundation
import PoseKit
import QuartzCore

/// Runs the front camera and Vision body pose detection on a background queue
/// and streams the results. Frames arrive upright and mirrored, so pose
/// coordinates line up with the (mirrored) camera preview.
final class PoseCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Sample: Sendable {
        let pose: PoseFrame?
        /// Seconds Vision took on this frame.
        let detectionTime: TimeInterval
    }

    enum CameraError: Error {
        case unavailable, cannotAddInput, cannotAddOutput
    }

    /// Portrait, for both the video output and the preview.
    static let rotationAngle: CGFloat = 90

    let session = AVCaptureSession()
    let samples: AsyncStream<Sample>
    private let continuation: AsyncStream<Sample>.Continuation
    private let queue = DispatchQueue(label: "com.dhsdb010.DancingStudio.camera")
    private let detector = VisionBodyPoseDetector()

    override init() {
        (samples, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        super.init()
    }

    /// Configures and starts the session. Throws `CameraError.unavailable`
    /// when there's no front camera, as in the Simulator.
    func start() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.configure()
                    self.session.startRunning()
                    done.resume()
                } catch {
                    done.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async { self.session.stopRunning() }
        continuation.finish()
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CameraError.unavailable
        }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720

        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        // Drop frames while Vision is busy instead of queueing them up.
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(Self.rotationAngle) {
                connection.videoRotationAngle = Self.rotationAngle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let start = CACurrentMediaTime()
        let pose = try? detector.detect(in: pixelBuffer, time: time)
        continuation.yield(Sample(pose: pose, detectionTime: CACurrentMediaTime() - start))
    }
}
