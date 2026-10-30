import SwiftUI

/// A Photos-style trimmer: a filmstrip with yellow handles for the start and
/// end, the rest dimmed. Beats are ticked along the strip, and the handles
/// snap to a beat when dragged close to one, so the start can land exactly on
/// the count "1". Dragging on the strip itself scrubs the preview.
struct ClipTrimmer: View {
    let duration: TimeInterval
    let thumbnails: [CGImage]
    /// Beat times across the whole video; empty when there's no beat.
    let beats: [TimeInterval]
    @Binding var start: TimeInterval
    @Binding var end: TimeInterval
    /// Where the preview is, drawn as a white line.
    var playhead: TimeInterval?
    /// Called with the time to show while a handle or the strip is dragged.
    var onScrub: (TimeInterval) -> Void
    var minimumLength: TimeInterval = 1

    @State private var dragOrigin: TimeInterval?
    @State private var lastSnap: TimeInterval?

    private let handleWidth: CGFloat = 16
    private let stripHeight: CGFloat = 52
    /// Points within which a handle snaps to a beat.
    private let snapDistance: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - handleWidth * 2
            let x = { (time: TimeInterval) in handleWidth + CGFloat(time / max(duration, 0.001)) * width }

            ZStack(alignment: .topLeading) {
                filmstrip
                    .frame(width: width, height: stripHeight)
                    .clipShape(.rect(cornerRadius: 4))
                    .offset(x: handleWidth)
                    .gesture(scrubGesture(width: width))

                beatTicks(width: width, x: x)

                // Dim what's trimmed away.
                Rectangle().fill(.black.opacity(0.55))
                    .frame(width: max(0, x(start) - handleWidth), height: stripHeight)
                    .offset(x: handleWidth)
                    .allowsHitTesting(false)
                Rectangle().fill(.black.opacity(0.55))
                    .frame(width: max(0, handleWidth + width - x(end)), height: stripHeight)
                    .offset(x: x(end))
                    .allowsHitTesting(false)

                // Selection frame.
                Rectangle()
                    .strokeBorder(.yellow, lineWidth: 3)
                    .frame(width: max(0, x(end) - x(start)), height: stripHeight)
                    .offset(x: x(start))
                    .allowsHitTesting(false)

                if let playhead, playhead >= start, playhead <= end {
                    Capsule().fill(.white)
                        .frame(width: 3, height: stripHeight + 8)
                        .offset(x: x(playhead) - 1.5, y: -4)
                        .shadow(radius: 1)
                        .allowsHitTesting(false)
                }

                handle(systemImage: "chevron.compact.left")
                    .offset(x: x(start) - handleWidth)
                    .gesture(handleGesture(isStart: true, width: width))
                    .accessibilityLabel("Start")
                    .accessibilityValue(PrepareRoutineView.format(start, precise: true))
                handle(systemImage: "chevron.compact.right")
                    .offset(x: x(end))
                    .gesture(handleGesture(isStart: false, width: width))
                    .accessibilityLabel("End")
                    .accessibilityValue(PrepareRoutineView.format(end, precise: true))
            }
        }
        .frame(height: stripHeight)
        .sensoryFeedback(.selection, trigger: lastSnap)
    }

    private var filmstrip: some View {
        HStack(spacing: 0) {
            if thumbnails.isEmpty {
                Color.gray.opacity(0.3)
            } else {
                ForEach(thumbnails.indices, id: \.self) { i in
                    Image(decorative: thumbnails[i], scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
        }
    }

    /// Small marks at the bottom of the strip, one per beat, when they're far
    /// enough apart to read.
    private func beatTicks(width: CGFloat, x: @escaping (TimeInterval) -> CGFloat) -> some View {
        Canvas { context, size in
            guard beats.count > 1, duration > 0, let first = beats.first, let last = beats.last else { return }
            let gap = (last - first) / Double(beats.count - 1)
            guard CGFloat(gap / duration) * width >= 3 else { return }
            var path = Path()
            for beat in beats {
                let px = x(beat)
                path.move(to: CGPoint(x: px, y: size.height - 8))
                path.addLine(to: CGPoint(x: px, y: size.height - 2))
            }
            context.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 1.5)
        }
        .frame(height: stripHeight)
        .allowsHitTesting(false)
    }

    private func handle(systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.yellow)
            .frame(width: handleWidth, height: stripHeight)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.7))
            }
            .contentShape(.rect.inset(by: -10))
    }

    private func handleGesture(isStart: Bool, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = dragOrigin ?? (isStart ? start : end)
                if dragOrigin == nil { dragOrigin = origin }
                var time = origin + Double(value.translation.width / width) * duration
                time = snapped(time, width: width)
                if isStart {
                    start = min(max(0, time), end - minimumLength)
                    onScrub(start)
                } else {
                    end = max(min(duration, time), start + minimumLength)
                    onScrub(end)
                }
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let time = Double(value.location.x / width) * duration
                onScrub(min(max(time, start), end))
            }
    }

    /// The nearest beat when it's within `snapDistance` points, else `time`.
    private func snapped(_ time: TimeInterval, width: CGFloat) -> TimeInterval {
        guard let beat = beats.min(by: { abs($0 - time) < abs($1 - time) }),
              CGFloat(abs(beat - time) / duration) * width < snapDistance else { return time }
        if beat != lastSnap { lastSnap = beat }
        return beat
    }
}
