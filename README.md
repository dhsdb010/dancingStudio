# Dancing Studio

An iOS app that turns a dance video into a step-by-step tutorial and coaches you in real time.

- **Learn any routine**: import a clip, and the app extracts the movement, slices it into steps and scores you live through the camera.
- **Studio practice**: teachers upload and slice practice videos, and students are notified and practise between classes, with slow-motion playback.
- **Memory library**: keep a personal collection of the moves you've learned.

See [docs/PLAN.md](docs/PLAN.md) for the research and roadmap.

## Layout
- `Packages/PoseKit`: pose data model and normalization. The Vision body/hand pose provider goes here too.
- `Packages/ChoreoKit`: segmentation and scoring, built on PoseKit.
- `DancingStudio.xcodeproj` and `DancingStudio/`: the SwiftUI app (iOS 17+). It uses folder-synced groups, so new files in `DancingStudio/` are added to the target automatically.

## Develop
```bash
swift test --package-path Packages/PoseKit
swift test --package-path Packages/ChoreoKit
xcodebuild -project DancingStudio.xcodeproj -scheme DancingStudio -destination 'generic/platform=iOS Simulator' build
```
To run on your iPhone, open the project in Xcode and choose your team under Signing & Capabilities. Live camera scoring only works on a real device.
Package tests need Xcode as the active developer directory (`xcode-select -p`). With only the Command Line Tools active, SwiftPM can't find the Swift Testing macros.
