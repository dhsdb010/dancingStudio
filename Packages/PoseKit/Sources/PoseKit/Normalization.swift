import Foundation

extension PoseFrame {
    /// Returns the frame centred on the hip midpoint and scaled so the torso
    /// (neck to hip midpoint) has length 1, which makes poses comparable across
    /// dancers, camera distances and positions in the frame.
    /// Returns nil when the hips or neck aren't confidently detected.
    public func normalized(mirror: Bool = false) -> PoseFrame? {
        guard let lHip = point(.leftHip), let rHip = point(.rightHip), let neck = point(.neck) else {
            return nil
        }
        let cx = (lHip.x + rHip.x) / 2
        let cy = (lHip.y + rHip.y) / 2
        let torso = hypot(neck.x - cx, neck.y - cy)
        guard torso > 0 else { return nil }

        var out: [BodyJoint: JointPoint] = [:]
        for (joint, p) in joints {
            var x = (p.x - cx) / torso
            let y = (p.y - cy) / torso
            if mirror { x = -x }
            out[mirror ? joint.mirrored : joint] = JointPoint(x: x, y: y, confidence: p.confidence)
        }
        return PoseFrame(time: time, joints: out)
    }
}
