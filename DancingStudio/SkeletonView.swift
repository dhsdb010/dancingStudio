import SwiftUI
import PoseKit
import ChoreoKit

/// Draws a pose as a stick figure. Joints are in Vision's normalized space
/// (0...1, origin bottom-left), so y is flipped for SwiftUI.
struct SkeletonView: View {
    let frame: PoseFrame
    var color: Color = .accentColor

    /// Limbs scored by ChoreoKit, plus the head and spine for display only.
    private static let bones: [Limb] = Limb.all + [
        Limb(from: .neck, to: .nose),
        Limb(from: .neck, to: .root),
    ]

    var body: some View {
        Canvas { context, size in
            func position(_ joint: BodyJoint) -> CGPoint? {
                guard let p = frame.point(joint) else { return nil }
                return CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
            }

            var bones = Path()
            for limb in Self.bones {
                guard let a = position(limb.from), let b = position(limb.to) else { continue }
                bones.move(to: a)
                bones.addLine(to: b)
            }
            context.stroke(bones, with: .color(color), style: StrokeStyle(lineWidth: 6, lineCap: .round))

            for joint in BodyJoint.allCases {
                guard let p = position(joint) else { continue }
                let r: CGFloat = joint == .nose ? 14 : 5
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color(color))
            }
        }
        .aspectRatio(0.6, contentMode: .fit)
        .accessibilityLabel("Dancer skeleton")
    }
}

#Preview {
    SkeletonView(frame: .samplePose)
        .padding()
}
