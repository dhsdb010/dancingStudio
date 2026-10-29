import Foundation

/// The 19 body joints reported by Vision's `VNDetectHumanBodyPoseRequest`.
/// Kept independent of Vision so the model and its math can be tested anywhere.
public enum BodyJoint: String, CaseIterable, Codable, Sendable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case neck, leftShoulder, rightShoulder
    case leftElbow, rightElbow, leftWrist, rightWrist
    case root, leftHip, rightHip
    case leftKnee, rightKnee, leftAnkle, rightAnkle

    /// The joint on the opposite side of the body (itself for centre joints).
    public var mirrored: BodyJoint {
        let name = rawValue
        if name.hasPrefix("left") { return BodyJoint(rawValue: "right" + name.dropFirst(4))! }
        if name.hasPrefix("right") { return BodyJoint(rawValue: "left" + name.dropFirst(5))! }
        return self
    }
}

public struct JointPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var confidence: Double

    public init(x: Double, y: Double, confidence: Double = 1) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

/// One video or camera frame of pose data.
public struct PoseFrame: Codable, Equatable, Sendable {
    /// Seconds from the start of the routine.
    public var time: TimeInterval
    public var joints: [BodyJoint: JointPoint]

    public init(time: TimeInterval, joints: [BodyJoint: JointPoint]) {
        self.time = time
        self.joints = joints
    }

    /// Joints at or above `minConfidence`.
    public func point(_ joint: BodyJoint, minConfidence: Double = 0.3) -> JointPoint? {
        guard let p = joints[joint], p.confidence >= minConfidence else { return nil }
        return p
    }
}
