import CoreVideo
import Testing
@testable import PoseKit

@Test func blankFrameHasNoPose() throws {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, 360, 640, kCVPixelFormatType_32BGRA, nil, &buffer)
    let pixelBuffer = try #require(buffer)
    #expect(try VisionBodyPoseDetector().detectAll(in: pixelBuffer, time: 0).isEmpty)
}

@Test func everyJointMapsToADistinctVisionJoint() {
    let names = Set(BodyJoint.allCases.map(\.visionName))
    #expect(names.count == BodyJoint.allCases.count)
}
