# Dancing Studio

An iOS app that turns a dance video into a step-by-step tutorial and coaches you in real time.

- **Learn any routine**: import a clip, and the app extracts the movement, slices it into steps and scores you live through the camera.
- **Studio practice**: teachers upload and slice practice videos, and students are notified and practise between classes, with slow-motion playback.
- **Memory library**: keep a personal collection of the moves you've learned.

See [docs/PLAN.md](docs/PLAN.md) for the research and roadmap.

## Layout
- `Packages/PoseKit`: pose data model and normalization. The Vision body/hand pose provider goes here too.
- `Packages/ChoreoKit`: segmentation and scoring, built on PoseKit.
- The iOS app target (SwiftUI) is not created yet. It needs Xcode 16+.

## Develop
```bash
swift test --package-path Packages/PoseKit
swift test --package-path Packages/ChoreoKit
```
With only the Command Line Tools installed (no Xcode), SwiftPM can't find the Swift Testing macros. Add this to the command:
`-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
