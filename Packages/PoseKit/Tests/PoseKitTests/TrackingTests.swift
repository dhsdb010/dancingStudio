import Foundation
import Testing
@testable import PoseKit

/// A rough standing figure centred at (cx, cy) with height `size`.
private func person(cx: Double, cy: Double = 0.5, size: Double = 0.4, time: TimeInterval = 0) -> PoseFrame {
    let h = size / 2
    let joints: [BodyJoint: JointPoint] = [
        .nose: JointPoint(x: cx, y: cy + h),
        .neck: JointPoint(x: cx, y: cy + h * 0.7),
        .leftShoulder: JointPoint(x: cx - h * 0.3, y: cy + h * 0.7),
        .rightShoulder: JointPoint(x: cx + h * 0.3, y: cy + h * 0.7),
        .leftHip: JointPoint(x: cx - h * 0.2, y: cy),
        .rightHip: JointPoint(x: cx + h * 0.2, y: cy),
        .leftAnkle: JointPoint(x: cx - h * 0.2, y: cy - h),
        .rightAnkle: JointPoint(x: cx + h * 0.2, y: cy - h),
    ]
    return PoseFrame(time: time, joints: joints)
}

@Test func locksOnToTheBiggestCentralPerson() {
    var tracker = PoseTracker()
    let main = person(cx: 0.5, size: 0.6)
    let side = person(cx: 0.9, size: 0.4)
    #expect(tracker.select(from: [side, main]) == main)
}

@Test func keepsFollowingTheSameDancerWhenSomeoneBiggerAppears() {
    var tracker = PoseTracker()
    _ = tracker.select(from: [person(cx: 0.5, size: 0.4)])
    let dancer = person(cx: 0.53, size: 0.4)
    let bigger = person(cx: 0.15, size: 0.8)
    #expect(tracker.select(from: [bigger, dancer]) == dancer)
}

@Test func reportsNothingInsteadOfJumpingToSomeoneElse() {
    var tracker = PoseTracker()
    _ = tracker.select(from: [person(cx: 0.5)])
    #expect(tracker.select(from: [person(cx: 0.95)]) == nil)
}

@Test func locksOnAgainAfterTheDancerIsLostForLong() {
    var tracker = PoseTracker()
    _ = tracker.select(from: [person(cx: 0.2)])
    for _ in 0...tracker.maxLostFrames { _ = tracker.select(from: []) }
    let newcomer = person(cx: 0.8)
    #expect(tracker.select(from: [newcomer]) == newcomer)
}

@Test func smootherKeepsAStillPoseStill() {
    var smoother = PoseSmoother()
    let pose = person(cx: 0.5)
    var out = pose
    for i in 0..<10 { out = smoother.smooth(PoseFrame(time: Double(i) / 30, joints: pose.joints)) }
    #expect(abs(out.joints[.neck]!.x - 0.5) < 1e-9)
}

@Test func smootherReducesJitter() {
    var smoother = PoseSmoother()
    var rawError = 0.0, smoothedError = 0.0
    for i in 0..<120 {
        let noise = (i % 2 == 0 ? 1.0 : -1.0) * 0.01
        var frame = person(cx: 0.5, time: Double(i) / 30)
        frame.joints[.leftWrist] = JointPoint(x: 0.3 + noise, y: 0.6)
        let out = smoother.smooth(frame)
        if i > 30 {
            rawError += abs(noise)
            smoothedError += abs(out.joints[.leftWrist]!.x - 0.3)
        }
    }
    #expect(smoothedError < rawError * 0.5)
}

@Test func smootherFollowsAFastMoveQuickly() {
    var smoother = PoseSmoother()
    var x = 0.0
    for i in 0..<30 {
        var frame = person(cx: 0.5, time: Double(i) / 30)
        frame.joints[.leftWrist] = JointPoint(x: i < 10 ? 0.2 : 0.6, y: 0.6)
        x = smoother.smooth(frame).joints[.leftWrist]!.x
    }
    #expect(abs(x - 0.6) < 0.01)
}

@Test func smootherHoldsABrieflyMissingJointThenDropsIt() {
    var smoother = PoseSmoother()
    var frame = person(cx: 0.5)
    _ = smoother.smooth(frame)
    frame.joints[.nose] = nil
    for i in 1...smoother.maxHeldFrames {
        frame.time = Double(i) / 30
        #expect(smoother.smooth(frame).joints[.nose] != nil)
    }
    frame.time = 1
    #expect(smoother.smooth(frame).joints[.nose] == nil)
}
