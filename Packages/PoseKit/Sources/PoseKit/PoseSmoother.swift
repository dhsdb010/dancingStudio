import Foundation

/// Reduces joint jitter with a One-Euro filter per joint coordinate: heavy
/// smoothing when a joint is still, little when it moves fast, so quick dance
/// moves don't lag. A joint that briefly drops below the confidence threshold
/// keeps its last position for up to `maxHeldFrames` frames instead of
/// flickering out.
public struct PoseSmoother: Sendable {
    /// Cutoff frequency (Hz) when a joint is still; lower is smoother.
    public var minCutoff = 1.5
    /// How quickly the cutoff rises with joint speed; higher means less lag.
    public var beta = 4.0
    public var derivativeCutoff = 1.0
    public var maxHeldFrames = 3

    private var filters: [BodyJoint: (x: OneEuroFilter, y: OneEuroFilter)] = [:]
    private var held: [BodyJoint: (point: JointPoint, frames: Int)] = [:]
    private var lastTime: TimeInterval?

    public init() {}

    /// Smooths the next frame of the same dancer. The result only contains
    /// confident (or briefly held) joints.
    public mutating func smooth(_ frame: PoseFrame) -> PoseFrame {
        let dt = lastTime.map { max(frame.time - $0, 0.001) } ?? 1.0 / 30
        lastTime = frame.time

        var joints: [BodyJoint: JointPoint] = [:]
        for joint in BodyJoint.allCases {
            if let p = frame.point(joint) {
                var filter = filters[joint] ?? (OneEuroFilter(), OneEuroFilter())
                let x = filter.x.filter(p.x, dt: dt, minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
                let y = filter.y.filter(p.y, dt: dt, minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
                filters[joint] = filter
                let smoothed = JointPoint(x: x, y: y, confidence: p.confidence)
                joints[joint] = smoothed
                held[joint] = (smoothed, 0)
            } else if let last = held[joint], last.frames < maxHeldFrames {
                joints[joint] = last.point
                held[joint] = (last.point, last.frames + 1)
            } else {
                filters[joint] = nil
                held[joint] = nil
            }
        }
        return PoseFrame(time: frame.time, joints: joints)
    }

    /// Forgets all history, e.g. after the tracked dancer was lost.
    public mutating func reset() {
        filters = [:]
        held = [:]
        lastTime = nil
    }
}

/// Casiez et al., "1€ Filter" (CHI 2012).
struct OneEuroFilter: Sendable {
    private var value: Double?
    private var derivative: Double = 0

    mutating func filter(_ x: Double, dt: TimeInterval, minCutoff: Double, beta: Double, derivativeCutoff: Double) -> Double {
        guard let previous = value else {
            value = x
            return x
        }
        let rawDerivative = (x - previous) / dt
        derivative += Self.alpha(cutoff: derivativeCutoff, dt: dt) * (rawDerivative - derivative)
        let cutoff = minCutoff + beta * abs(derivative)
        let result = previous + Self.alpha(cutoff: cutoff, dt: dt) * (x - previous)
        value = result
        return result
    }

    private static func alpha(cutoff: Double, dt: TimeInterval) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}
