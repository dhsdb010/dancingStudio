import Foundation
import Testing
import PoseKit
@testable import ChoreoKit

/// A figure facing the camera with both arms at `armAngle` radians
/// (0 = straight out to the sides, π/2 = up). Its "left" joints are on the
/// right of the screen, as Vision labels a person facing the camera.
private func figure(time: TimeInterval, armAngle: Double) -> PoseFrame {
    let c = cos(armAngle) * 0.1, s = sin(armAngle) * 0.1
    let points: [BodyJoint: (Double, Double)] = [
        .neck: (0.5, 0.7),
        .leftShoulder: (0.58, 0.7), .rightShoulder: (0.42, 0.7),
        .leftElbow: (0.58 + c, 0.7 + s), .rightElbow: (0.42 - c, 0.7 + s),
        .leftWrist: (0.58 + 2 * c, 0.7 + 2 * s), .rightWrist: (0.42 - 2 * c, 0.7 + 2 * s),
        .leftHip: (0.55, 0.45), .rightHip: (0.45, 0.45),
        .leftKnee: (0.55, 0.25), .rightKnee: (0.45, 0.25),
        .leftAnkle: (0.55, 0.05), .rightAnkle: (0.45, 0.05),
    ]
    return PoseFrame(time: time, joints: points.mapValues { JointPoint(x: $0.0, y: $0.1) })
}

/// Arms swing up, back down past the sides and back over two seconds.
private func swingAngle(_ t: TimeInterval) -> Double { sin(t * .pi) * .pi / 2 }

private func routine(angle: (TimeInterval) -> Double = swingAngle) -> PoseSequence {
    let frames = (0..<60).map { i in figure(time: Double(i) / 30, armAngle: angle(Double(i) / 30)) }
    return PoseSequence(start: 0, end: 2, frames: frames)
}

/// Feeds two seconds of live frames at 30 fps and returns every step result.
private func dance(_ scorer: inout PracticeScorer, user: (TimeInterval) -> PoseFrame?) -> [StepResult] {
    for i in 0..<60 {
        let t = Double(i) / 30
        scorer.add(user: user(t), at: t)
    }
    scorer.finish()
    return scorer.results
}

private func scorer(_ reference: PoseSequence) -> PracticeScorer {
    PracticeScorer(reference: reference, referenceAspect: 1, userAspect: 1)
}

@Test func matchingTheRoutineIsPerfect() {
    var s = scorer(routine())
    let results = dance(&s) { figure(time: $0, armAngle: swingAngle($0)) }
    #expect(results.map(\.index) == [0, 1, 2, 3])
    #expect(results.allSatisfy { $0.rating == .perfect && $0.feedback == nil })
}

@Test func dancingSlightlyLateIsStillPerfect() {
    var s = scorer(routine())
    let results = dance(&s) { figure(time: $0, armAngle: swingAngle(max(0, $0 - 0.2))) }
    #expect(results.allSatisfy { $0.rating == .perfect })
}

@Test func wrongMoveIsAMissWithARaiseHint() throws {
    var s = scorer(routine { _ in .pi / 2 })
    let results = dance(&s) { figure(time: $0, armAngle: -.pi / 2) }
    #expect(results.allSatisfy { $0.rating == .miss })
    let feedback = try #require(results.first?.feedback)
    #expect(feedback == LimbFeedback(part: .upperArm, side: .right, hint: .raise))
    #expect(s.commonFeedback() == [feedback])
}

@Test func noDancerInFrameIsAMiss() {
    var s = scorer(routine())
    let results = dance(&s) { _ in nil }
    #expect(results.count == 4)
    #expect(results.allSatisfy { $0.rating == .miss && $0.similarity == 0 })
}

@Test func stretchesWithoutAReferenceDancerAreNotScored() {
    let empty = PoseSequence(start: 0, end: 2, frames: (0..<60).map { PoseFrame(time: Double($0) / 30, joints: [:]) })
    var s = scorer(empty)
    #expect(dance(&s) { figure(time: $0, armAngle: 0) }.isEmpty)
}

@Test func swappedLeftRightLabelsStillMatch() {
    var s = scorer(routine { _ in 0 })
    let results = dance(&s) { figure(time: $0, armAngle: 0).swappingSides() }
    #expect(results.allSatisfy { $0.rating == .perfect })
}

@Test func loopingBackClosesTheStep() {
    var s = scorer(routine())
    for pass in 0..<2 {
        for i in 0..<30 {
            let t = Double(i) / 30
            s.add(user: figure(time: t, armAngle: swingAngle(t)), at: t)
        }
        if pass == 1 { s.finish() }
    }
    #expect(s.results.map(\.index) == [0, 1, 0, 1])
}

@Test func aspectRatioIsAppliedBeforeComparing() {
    // The same 45° arm, stored in a frame half as wide as it is tall, has its
    // x coordinates doubled in normalized units.
    let wide = figure(time: 0, armAngle: .pi / 4)
    let narrow = PoseFrame(time: 0, joints: wide.joints.mapValues { JointPoint(x: 0.5 + ($0.x - 0.5) * 2, y: $0.y) })
    var s = PracticeScorer(reference: PoseSequence(start: 0, end: 1, frames: [wide]), referenceAspect: 1, userAspect: 0.5)
    s.add(user: narrow, at: 0)
    #expect(s.finish()?.rating == .perfect)
}

@Test func reactingHalfASecondLateIsStillPerfect() {
    var s = scorer(routine())
    let results = dance(&s) { figure(time: $0, armAngle: swingAngle(max(0, $0 - 0.45))) }
    #expect(results.allSatisfy { $0.rating == .perfect })
}

@Test func beingWellAheadIsMarkedDown() {
    var s = scorer(routine())
    let results = dance(&s) { figure(time: $0, armAngle: swingAngle($0 + 0.45)) }
    #expect(results.contains { $0.rating != .perfect })
}

@Test func frameSimilarityFollowsTheLatestFrame() {
    var s = scorer(routine())
    s.add(user: figure(time: 0, armAngle: 0), at: 0)
    #expect(s.frameSimilarity == 1)
    s.add(user: nil, at: 0.1)
    #expect(s.frameSimilarity == 0)

    let empty = PoseSequence(start: 0, end: 1, frames: [PoseFrame(time: 0, joints: [:])])
    var nothing = scorer(empty)
    nothing.add(user: figure(time: 0, armAngle: 0), at: 0)
    #expect(nothing.frameSimilarity == nil)
}

@Test func tipNamesTheSideWhenOnlyTheUpperBodyIsVisible() throws {
    var s = scorer(routine { _ in .pi / 2 })
    let armsOnly: Set<BodyJoint> = [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist]
    for i in 0..<15 {
        let t = Double(i) / 30
        var user = figure(time: t, armAngle: -.pi / 2)
        user.joints = user.joints.filter { armsOnly.contains($0.key) }
        s.add(user: user, at: t)
    }
    let feedback = try #require(s.finish()?.feedback)
    #expect(feedback.side == .right)
}
