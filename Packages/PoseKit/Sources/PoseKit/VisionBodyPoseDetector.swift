import CoreVideo
import ImageIO
import Vision

/// Detects a body pose in one frame with Vision's `VNDetectHumanBodyPoseRequest`.
/// Coordinates stay in Vision's normalized space (0...1, origin bottom-left)
/// relative to the image as oriented by `orientation`.
public struct VisionBodyPoseDetector: Sendable {
    public init() {}

    /// Returns one pose per person Vision finds, in no particular order.
    /// Use `PoseTracker` to follow one dancer across frames.
    public func detectAll(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .up,
        time: TimeInterval
    ) throws -> [PoseFrame] {
        let request = VNDetectHumanBodyPoseRequest()
        try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation).perform([request])

        return try (request.results ?? []).map { observation in
            let points = try observation.recognizedPoints(.all)
            var joints: [BodyJoint: JointPoint] = [:]
            for joint in BodyJoint.allCases {
                guard let p = points[joint.visionName] else { continue }
                joints[joint] = JointPoint(x: p.location.x, y: p.location.y, confidence: Double(p.confidence))
            }
            return PoseFrame(time: time, joints: joints)
        }
    }
}

extension BodyJoint {
    var visionName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .nose: .nose
        case .leftEye: .leftEye
        case .rightEye: .rightEye
        case .leftEar: .leftEar
        case .rightEar: .rightEar
        case .neck: .neck
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        case .leftElbow: .leftElbow
        case .rightElbow: .rightElbow
        case .leftWrist: .leftWrist
        case .rightWrist: .rightWrist
        case .root: .root
        case .leftHip: .leftHip
        case .rightHip: .rightHip
        case .leftKnee: .leftKnee
        case .rightKnee: .rightKnee
        case .leftAnkle: .leftAnkle
        case .rightAnkle: .rightAnkle
        }
    }
}
