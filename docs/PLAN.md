# Dancing Studio: research findings and build plan (iOS first)

## Context
`dhsdb010/dancingStudio` is an empty repo. The goal is an iOS app that turns a dance video into a step-by-step tutorial and coaches the user in real time, similar in feel to Just Dance.
- **Solo learners** import a clip (for example 1:00–1:30 of a video). The app extracts the movement, slices it into steps, and scores the user live through the camera.
- **Studios**: teachers upload practice videos and slice them into parts. Students get a push notification and practise between classes, with slow-motion playback.
- **Memory library**: each user keeps a personal collection of the moves they've learned.

This plan records what the research found and proposes an architecture and phased roadmap. It starts with a short spike to reduce the technical risk.

## Research findings

### The three suggested open-source projects
| Project | What it is | Runs on iOS? | License | Verdict |
|---|---|---|---|---|
| MocapNET (FORTH) | Turns 2D joints from RGB video into 3D BVH. C++/TensorFlow (v2) or Python with MediaPipe and Blender (v4). | No (Linux desktop) | FORTH custom license; needs checking for commercial use | Optional later: server-side 3D/BVH export |
| toyxyz RGBMocap | Windows GUI app: video in, FBX/VMD out (GVHMR and similar models) | No (Windows, NVIDIA GPU, ~45 GB) | MIT, but the model files have their own licenses | Not usable in-app. Possibly useful as an offline tool for making 3D avatar animations |
| FreeMoCap | Research mocap with a Python server and Electron GUI, mainly multi-camera | No | AGPL-3.0, which is a risk for a closed-source app | Reference only |

**Conclusion:** none of the three can be embedded in an iOS app. Do the core pipeline on-device, and keep these projects as candidates for an optional future server path that produces 3D avatar replays.

### On-device pose options
- **Apple Vision `VNDetectHumanBodyPoseRequest` (2D, 19 joints)** is free, built in, runs in real time and needs no extra dependency. **This is the recommended starting point.**
- **Apple Vision 3D (`VNDetectHumanBodyPose3DRequest`, iOS 17+, 17 joints)** gives camera-relative 3D joints. Forum threads report problems with it, so try it in the spike for offline analysis of reference videos.
- **Apple Vision `VNDetectHumanHandPoseRequest` (21 points per hand)** covers the wrist plus 4 points on each finger. `maximumHandCount` defaults to 2; raising it costs performance.
  - It fills Vision body pose's biggest gap: body pose stops at the wrist, so hand shape (open hand, fist, pointing, finger tutting) isn't scored without it.
  - **Risk:** in a full-body dance shot, hands are small and blur during fast moves, so confidence drops. To mitigate this, crop the hand request to a `regionOfInterest` around each wrist. Treat hand scoring as a bonus or secondary signal and gate it by confidence.
  - `regionOfInterest` must be set before `perform()` is called, so the wrist ROI can't come from the same `perform([body, hand])` call. Each mode gets its own sequence:
    - **Offline (reference video):** call `perform()` twice on the same buffer. First run `perform([bodyRequest])`, then set each hand request's `regionOfInterest` from this frame's wrist joints, then run `perform([handRequest…])`. The extra pass is fine because offline processing isn't latency-bound. If the wrist confidence is low, skip the ROI and run hands on the full frame.
    - **Live (practice):** a single `perform([bodyRequest, handRequest])` per frame. The hand ROI comes from the **previous frame's** wrist joints, expanded by a margin that covers motion between frames. On the first frame, or when the previous wrist is missing or low-confidence, run hands on the full frame. If fps is too low, run the hand request only every 2nd or 3rd frame; the spike will measure this.
  - Hand results don't say which body they belong to. Match each hand to the person by the distance from the hand's wrist point to the body's wrist joint, and use `chirality` (left or right) on iOS 15+.
- **MediaPipe BlazePose / ML Kit Pose (33 keypoints)** adds coarse hand and foot points (heel, toe). It's the fallback if Vision's 19 body joints plus hand pose still miss footwork.
- Put pose detection behind a `PoseProvider` protocol so the backend can be swapped.

### Scoring approach (from the literature)
1. Normalize each frame: centre on the hip midpoint, scale by torso length, and optionally mirror so the user can face the screen.
2. Build per-frame features from joint angles (elbows, shoulders, hips, knees) and limb direction vectors.
3. Score each frame with cosine similarity and angle error.
4. Align timing with DTW over a sliding window (about ±300 ms) so slight lateness isn't punished. Rate each beat as Perfect, Good, OK or Miss.
5. Give per-limb feedback ("left arm too low") from the joint with the largest error.
6. Score hand shape separately from finger joint angles (open, fist, point and similar), weight it lower, and only when hand confidence is above a threshold in both the reference and the live frame.

Published student and academic systems report roughly 15% disagreement with human judges. Expect to tune the scoring with real dancers.

## Recommended architecture

**Client:** native Swift and SwiftUI, iOS 17+.
- AVFoundation handles capture and playback. Slow-down uses `AVPlayer.rate` between 0.25× and 1.0× with pitch-preserving `audioTimePitchAlgorithm`, and the scoring timeline scales to match.
- A skeleton overlay ("simulated dancer") is rendered with SwiftUI Canvas or SpriteKit. A 3D avatar in RealityKit comes later.

**Swift packages** (testable with `swift test`, no simulator needed):
- `PoseKit`: `PoseProvider` protocol, the Vision implementation (body pose plus wrist-cropped hand pose; offline does two passes per frame, live uses the previous frame's wrist ROI), the `PoseFrame` model (body joints plus optional left and right hand joints, each with a confidence), `PoseSequence` and normalization. Hands are normalized relative to their own wrist and palm size.
- `ChoreoKit`:
  - Segmentation: audio beat and onset detection with Accelerate FFT, plus motion-pause detection from joint-velocity minima. The output is suggested cut points in 8-counts that a teacher can edit.
  - Scoring: features, windowed DTW and ratings.
- `DancingStudioApp`: UI, persistence and networking.

**Processing a reference video (all on-device):** trim → frame sampling at 30 fps → pose extraction → smoothing (One-Euro filter) → segmentation → save a `Routine`. A `Routine` holds the video, keypoint JSON, segments, BPM and metadata. A 30-second clip should take seconds to minutes in a background task with progress shown.

**Practice mode:**
- Split screen: the reference video or skeleton on one side, the mirrored front camera with a live skeleton on the other.
- Each segment can loop at a chosen speed. Live scoring rates each beat, and a summary at the end shows the weakest moves.

**Backend for studio features:** Firebase (Auth, Firestore, Storage, Cloud Messaging/APNs, Cloud Functions to send "new practice video" notifications).
- Data model: Studio → Classes → Members (teacher or student roles) → Assignments (Routine reference).
- Teachers' devices do the processing and upload the processed keypoints with the video, so students don't need to re-analyse.
- *Alternative:* Supabase, if you'd rather use SQL and avoid Google lock-in.

**Local data:** SwiftData for the memory library (saved Routines and segments, practice history and scores), synced to Firestore when signed in.

**Copyright and policy:** accept videos only from Photos or Files, never by downloading from YouTube or TikTok. Keep personal imports private and on-device. Only studio-owned videos are shared.

## Phased roadmap
0. **Spike (about 2 weeks), to reduce risk:**
   - Measure Vision 2D vs 3D vs MediaPipe on 5–10 real dance clips: joint jitter, fast spins, occlusion, loose clothing.
   - Measure hand pose recall in full-body framing for three setups: full frame, same-frame wrist ROI (offline two-pass) and previous-frame wrist ROI (live). Tune the ROI margin on fast arm moves.
  - Measure live fps on the oldest target iPhone for body only, body plus hands on every frame, and body plus hands on every 3rd frame.
   - Prototype the scoring and compare it with a teacher's judgement.
   - Decide the pose backend and the minimum iPhone.
1. **MVP (solo):** import and trim a video → process → auto-slice with manual adjustment → practise a segment with slow-down and live scoring → results screen.
2. **Studio:** accounts and roles, studio and class creation with invite codes, teacher upload and slicing editor, assignment push notifications, and a view of student progress for teachers.
3. **Library and polish:** the memory library, streaks and history, 3D avatar replay, and optional server-side MocapNET or GVHMR for higher-quality 3D.

## Repo setup (first implementation step after approval)
- An Xcode project `DancingStudio` with local packages `PoseKit` and `ChoreoKit`.
- `.gitignore` for Xcode and SwiftPM.
- A README with the vision, and a real `CLAUDE.md` once code exists (re-run `/init`).

## Verification
- **Unit tests** (`swift test` in each package):
  - Normalization is invariant to translation and scale.
  - Scoring gives an identical sequence about 100%, a time-shifted copy a high score, and a mirrored or wrong move a low score.
  - Segmentation finds beat-aligned cuts on a metronome audio fixture.
- **Spike benchmark script:** run pose extraction over the sample clips and log jitter and fps.
- **On-device testing:** the camera needs a physical iPhone because the simulator has none. Use the iOS Simulator only for the UI flows.
- **Studio flow:** use the Firebase emulator suite locally (Auth, Firestore, Functions) before hitting production.

## Open items for you
- Do you have an Apple Developer account, a Mac with Xcode 16+, and a test iPhone?
- Confirm Firebase (vs Supabase).
- Confirm iOS 17 as the minimum version.

## Sources
[MocapNET](https://github.com/FORTH-ModelBasedTracker/MocapNET) · [RGBMocap](https://github.com/toyxyz/toyxyz_RGBMocap) · [FreeMoCap](https://github.com/freemocap/freemocap) · [Detect body and hand pose (WWDC20)](https://www.wwdcnotes.com/notes/wwdc20/10653/) · [VNDetectHumanHandPoseRequest](https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest) · [Vision 3D body pose (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/111241/) · [VNDetectHumanBodyPose3DRequest](https://developer.apple.com/documentation/vision/vndetecthumanbodypose3drequest) · [BlazePose](https://www.research.google/blog/on-device-real-time-body-pose-tracking-with-mediapipe-blazepose/) · [UCI dance pose estimation (DTW and cosine)](https://projects.eng.uci.edu/projects/2025-2026/dance-pose-estimation) · [Pose-sequence alignment](https://arxiv.org/pdf/2303.04244)
