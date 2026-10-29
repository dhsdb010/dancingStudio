import Testing
import PoseKit
@testable import ChoreoKit

private func pose(leftWrist: (Double, Double)) -> PoseFrame {
    let raw: [BodyJoint: (Double, Double)] = [
        .leftShoulder: (-1, 2), .rightShoulder: (1, 2),
        .leftElbow: (-2, 2), .rightElbow: (2, 2),
        .leftWrist: leftWrist, .rightWrist: (3, 2),
        .leftHip: (-0.5, 0), .rightHip: (0.5, 0),
    ]
    return PoseFrame(time: 0, joints: raw.mapValues { JointPoint(x: $0.0, y: $0.1) })
}

@Test func identicalPosesScorePerfect() throws {
    let p = pose(leftWrist: (-3, 2))
    let score = try #require(scoreFrame(reference: p, user: p))
    #expect(abs(score.similarity - 1) < 1e-9)
}

@Test func differentArmLowersScoreAndIsReported() throws {
    let reference = pose(leftWrist: (-2, 3))  // forearm pointing up
    let user = pose(leftWrist: (-2, 1))       // forearm pointing down
    let score = try #require(scoreFrame(reference: reference, user: user))
    #expect(score.similarity < 0.95)
    #expect(score.worstLimb == Limb(from: .leftElbow, to: .leftWrist))
}

@Test func noSharedLimbsReturnsNil() {
    let empty = PoseFrame(time: 0, joints: [:])
    #expect(scoreFrame(reference: empty, user: pose(leftWrist: (-3, 2))) == nil)
}
