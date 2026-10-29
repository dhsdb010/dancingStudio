import Foundation

/// Follows one dancer across frames when several people are in view.
/// It locks on to the biggest, most central person, then keeps choosing the
/// candidate closest to where that dancer was last seen. If the dancer is lost
/// for longer than `maxLostFrames`, it locks on again from scratch.
public struct PoseTracker: Sendable {
    /// How far (in normalized image units) the dancer's torso may move between
    /// consecutive frames and still count as the same person.
    public var maxJump = 0.15
    /// Extra distance allowed per frame the dancer has been missing.
    public var jumpGrowthPerLostFrame = 0.02
    public var maxLostFrames = 30

    private var lastAnchor: JointPoint?
    private var lostFrames = 0

    public init() {}

    /// Returns the tracked dancer's pose among `candidates`, or nil when they
    /// aren't among them.
    public mutating func select(from candidates: [PoseFrame]) -> PoseFrame? {
        let anchored = candidates.compactMap { pose in pose.anchor.map { (pose, $0) } }

        if let last = lastAnchor, lostFrames <= maxLostFrames {
            let allowed = maxJump + jumpGrowthPerLostFrame * Double(lostFrames)
            let nearest = anchored
                .map { (pose: $0.0, anchor: $0.1, distance: hypot($0.1.x - last.x, $0.1.y - last.y)) }
                .min { $0.distance < $1.distance }
            if let nearest, nearest.distance <= allowed {
                lastAnchor = nearest.anchor
                lostFrames = 0
                return nearest.pose
            }
            lostFrames += 1
            return nil
        }

        guard let pick = anchored.max(by: { Self.prominence($0.0, $0.1) < Self.prominence($1.0, $1.1) }) else {
            lastAnchor = nil
            return nil
        }
        lastAnchor = pick.1
        lostFrames = 0
        return pick.0
    }

    /// Bigger and closer to the centre of the frame scores higher.
    private static func prominence(_ pose: PoseFrame, _ anchor: JointPoint) -> Double {
        let offCentre = min(0.9, hypot(anchor.x - 0.5, anchor.y - 0.5))
        return pose.boundingArea * (1 - offCentre)
    }
}

extension PoseFrame {
    /// The centre of the confidently detected torso joints (falling back to all
    /// confident joints), used to recognise the same person in the next frame.
    var anchor: JointPoint? {
        let torso: [BodyJoint] = [.neck, .root, .leftShoulder, .rightShoulder, .leftHip, .rightHip]
        var points = torso.compactMap { point($0) }
        if points.isEmpty { points = BodyJoint.allCases.compactMap { point($0) } }
        guard !points.isEmpty else { return nil }
        let n = Double(points.count)
        return JointPoint(x: points.map(\.x).reduce(0, +) / n, y: points.map(\.y).reduce(0, +) / n)
    }

    /// Area of the box around the confident joints, in normalized image units.
    var boundingArea: Double {
        let points = BodyJoint.allCases.compactMap { point($0) }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return 0 }
        return (maxX - minX) * (maxY - minY)
    }
}
