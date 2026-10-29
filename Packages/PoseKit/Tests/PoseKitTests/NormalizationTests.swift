import Testing
@testable import PoseKit

func samplePose(offsetX: Double = 0, offsetY: Double = 0, scale: Double = 1) -> PoseFrame {
    let raw: [BodyJoint: (Double, Double)] = [
        .neck: (0, 2), .leftHip: (-0.5, 0), .rightHip: (0.5, 0),
        .leftShoulder: (-1, 2), .rightShoulder: (1, 2),
        .leftWrist: (-2, 3), .rightWrist: (2, 1),
    ]
    return PoseFrame(time: 0, joints: raw.mapValues {
        JointPoint(x: $0.0 * scale + offsetX, y: $0.1 * scale + offsetY)
    })
}

@Test func normalizationIsTranslationAndScaleInvariant() throws {
    let a = try #require(samplePose().normalized())
    let b = try #require(samplePose(offsetX: 0.3, offsetY: -0.2, scale: 0.25).normalized())
    for joint in a.joints.keys {
        #expect(abs(a.joints[joint]!.x - b.joints[joint]!.x) < 1e-9)
        #expect(abs(a.joints[joint]!.y - b.joints[joint]!.y) < 1e-9)
    }
}

@Test func mirroringSwapsSidesAndFlipsX() throws {
    let m = try #require(samplePose().normalized(mirror: true))
    let n = try #require(samplePose().normalized())
    #expect(m.joints[.leftWrist]!.x == -n.joints[.rightWrist]!.x)
    #expect(m.joints[.leftWrist]!.y == n.joints[.rightWrist]!.y)
}

@Test func missingHipsReturnsNil() {
    var pose = samplePose()
    pose.joints[.leftHip] = nil
    #expect(pose.normalized() == nil)
}
