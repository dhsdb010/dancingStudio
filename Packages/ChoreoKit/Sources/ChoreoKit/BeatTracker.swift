import Accelerate
import Foundation

/// A steady beat found in a stretch of music.
public struct BeatGrid: Codable, Equatable, Sendable {
    public var bpm: Double
    /// Beat times in seconds, on the same timeline as the audio passed in.
    public var beats: [TimeInterval]
    /// Index into `beats` of the first bar downbeat, the dancer's "1".
    public var firstDownbeat: Int

    public init(bpm: Double, beats: [TimeInterval], firstDownbeat: Int) {
        self.bpm = bpm
        self.beats = beats
        self.firstDownbeat = firstDownbeat
    }

    /// The beats between `start` and `end`, counting from `start`: the first
    /// beat at (or a quarter beat before) `start` becomes the "1". This is how
    /// a trim sets where the counts begin. Nil when fewer than two beats remain.
    public func trimmed(from start: TimeInterval, to end: TimeInterval) -> BeatGrid? {
        let tolerance = 60 / bpm / 4
        let kept = beats.filter { $0 >= start - tolerance && $0 <= end }
        guard kept.count >= 2 else { return nil }
        return BeatGrid(bpm: bpm, beats: kept, firstDownbeat: 0)
    }

    /// The beat nearest `time`, or nil without beats.
    public func nearestBeat(to time: TimeInterval) -> TimeInterval? {
        beats.min { abs($0 - time) < abs($1 - time) }
    }

    /// The dancer's count (1–8) at `time`. Beats before the first downbeat
    /// count in as the end of a phrase ("6, 7, 8"), and the moment before the
    /// first detected beat counts as the beat before it, so a loop that starts
    /// just ahead of the beat doesn't blank the count. Nil outside the beats.
    public func count(at time: TimeInterval) -> Int? {
        guard let first = beats.first else { return nil }
        let beat = 60 / bpm
        // A frame landing a hair before a beat (a video frame vs. the detected
        // onset) shows that beat's count.
        let early = min(0.05, beat / 8)
        let index: Int
        if let last = beats.lastIndex(where: { $0 <= time + early }) {
            guard time - beats[last] < beat * 1.5 else { return nil }
            index = last
        } else {
            guard time >= first - beat else { return nil }
            index = -1
        }
        let offset = (index - firstDownbeat) % 8
        return (offset + 8) % 8 + 1
    }
}

/// Finds the tempo and beat positions of music with a steady beat, as in most
/// dance tracks. It builds an onset envelope (spectral flux: how much louder
/// each frequency band got since the previous frame), picks the tempo whose
/// period best repeats in that envelope, then the beat phase that lands on the
/// strongest onsets. The downbeat is the beat position within the bar with the
/// strongest accents, usually the kick drum.
public struct BeatTracker: Sendable {
    public var minBPM = 70.0
    public var maxBPM = 180.0
    /// Tempos near this are preferred when two candidates are close, which
    /// avoids picking half or double the real tempo.
    public var preferredBPM = 120.0

    private let frameSize = 1024
    private let hopSize = 512

    public init() {}

    /// `samples` is mono audio at `sampleRate`; `startTime` is the time of the
    /// first sample, added to the returned beat times. Returns nil when there's
    /// too little audio or no clear beat.
    public func track(samples: [Float], sampleRate: Double, startTime: TimeInterval = 0) -> BeatGrid? {
        let envelope = onsetEnvelope(samples)
        let frameRate = sampleRate / Double(hopSize)
        let maxLag = Int(60 * frameRate / minBPM)
        guard envelope.count > maxLag * 4,
              let estimate = beatPeriod(envelope, frameRate: frameRate) else { return nil }

        let (phase, period) = refine(envelope, phase: bestPhase(envelope, period: estimate), period: estimate)
        // Beat k sits at frame `phase + k * period`. Frame f covers the audio
        // from f * hop, and flux peaks once an onset is well inside the
        // window: measured on click tracks as 29.5 ms (±0.5 ms) after f * hop.
        let offset = 0.0295
        var beats: [TimeInterval] = []
        var frame = phase
        while frame < Double(envelope.count) {
            beats.append(startTime + frame / frameRate + offset)
            frame += period
        }
        guard beats.count >= 4 else { return nil }

        let accents = beats.indices.map { strength(envelope, at: phase + Double($0) * period) }
        let firstDownbeat = (0..<4).max { a, b in
            barAccent(accents, offset: a) < barAccent(accents, offset: b)
        }!
        return BeatGrid(bpm: 60 * frameRate / period, beats: beats, firstDownbeat: firstDownbeat)
    }

    /// Half-wave rectified spectral flux of log magnitudes, with a local mean
    /// subtracted so steady loud passages don't count as onsets.
    private func onsetEnvelope(_ samples: [Float]) -> [Float] {
        guard samples.count >= frameSize,
              let dft = try? vDSP.DiscreteFourierTransform(count: frameSize, direction: .forward,
                                                           transformType: .complexComplex, ofType: Float.self)
        else { return [] }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: frameSize, isHalfWindow: false)
        let zeros = [Float](repeating: 0, count: frameSize)
        var real = [Float](repeating: 0, count: frameSize)
        var imaginary = [Float](repeating: 0, count: frameSize)
        var previous = [Float](repeating: 0, count: frameSize / 2)
        var flux: [Float] = []

        var start = 0
        while start + frameSize <= samples.count {
            let frame = vDSP.multiply(samples[start..<start + frameSize], window)
            dft.transform(inputReal: frame, inputImaginary: zeros, outputReal: &real, outputImaginary: &imaginary)
            var magnitudes = [Float](repeating: 0, count: frameSize / 2)
            for i in 0..<frameSize / 2 {
                magnitudes[i] = log1p(100 * (real[i] * real[i] + imaginary[i] * imaginary[i]).squareRoot())
            }
            var sum: Float = 0
            for i in 0..<magnitudes.count { sum += max(0, magnitudes[i] - previous[i]) }
            flux.append(sum)
            previous = magnitudes
            start += hopSize
        }
        guard !flux.isEmpty else { return [] }
        flux[0] = 0  // the first frame has nothing to compare against

        // Subtract a ~0.25 s moving average and keep what rises above it.
        let radius = 5
        return flux.indices.map { i in
            let window = flux[max(0, i - radius)...min(flux.count - 1, i + radius)]
            let mean = window.reduce(0, +) / Float(window.count)
            return max(0, flux[i] - mean)
        }
    }

    /// The beat period in envelope frames (fractional), from the
    /// autocorrelation peak within the tempo range, weighted toward
    /// `preferredBPM`.
    private func beatPeriod(_ envelope: [Float], frameRate: Double) -> Double? {
        let minLag = max(1, Int(60 * frameRate / maxBPM))
        let maxLag = Int(60 * frameRate / minBPM)
        func autocorrelation(_ lag: Int) -> Double {
            var sum: Float = 0
            for i in 0..<(envelope.count - lag) { sum += envelope[i] * envelope[i + lag] }
            return Double(sum) / Double(envelope.count - lag)
        }
        let values = (minLag - 1...maxLag + 1).map { autocorrelation($0) }
        func value(_ lag: Int) -> Double { values[lag - (minLag - 1)] }

        var best: (lag: Int, score: Double)?
        for lag in minLag...maxLag {
            let bpm = 60 * frameRate / Double(lag)
            // Log-normal tempo prior, one octave wide.
            let prior = exp(-0.5 * pow(log2(bpm / preferredBPM), 2))
            let score = value(lag) * prior
            if score > best?.score ?? 0 { best = (lag, score) }
        }
        guard let best, value(best.lag) > 0 else { return nil }

        // Parabolic interpolation around the peak for a sub-frame period.
        let (a, b, c) = (value(best.lag - 1), value(best.lag), value(best.lag + 1))
        let denominator = a - 2 * b + c
        let shift = denominator < 0 ? 0.5 * (a - c) / denominator : 0
        return Double(best.lag) + max(-0.5, min(0.5, shift))
    }

    /// The starting frame (0 ..< period) whose beat grid collects the most
    /// onset strength.
    private func bestPhase(_ envelope: [Float], period: Double) -> Double {
        var best: (phase: Double, score: Float) = (0, -1)
        var phase = 0.0
        while phase < period {
            var score: Float = 0
            var frame = phase
            while frame < Double(envelope.count) {
                score += strength(envelope, at: frame)
                frame += period
            }
            if score > best.score { best = (phase, score) }
            phase += 0.5
        }
        return best.phase
    }

    /// Snaps each predicted beat to the onset peak near it (to a fraction of a
    /// frame) and fits a straight line through them, which pins the period and
    /// phase down far more precisely than the autocorrelation lag. Weak peaks
    /// (off-beat noise) are left out of the fit.
    private func refine(_ envelope: [Float], phase: Double, period: Double) -> (phase: Double, period: Double) {
        var peaks: [(beat: Double, frame: Double, strength: Float)] = []
        var k = 0.0
        while phase + k * period < Double(envelope.count) {
            let predicted = phase + k * period
            let range = max(0, Int(predicted - period / 4))...min(envelope.count - 1, Int(predicted + period / 4))
            let i = range.max { envelope[$0] < envelope[$1] }!
            var frame = Double(i)
            if i > 0, i < envelope.count - 1 {
                let (a, b, c) = (Double(envelope[i - 1]), Double(envelope[i]), Double(envelope[i + 1]))
                let denominator = a - 2 * b + c
                if denominator < 0 { frame += max(-0.5, min(0.5, 0.5 * (a - c) / denominator)) }
            }
            peaks.append((k, frame, envelope[i]))
            k += 1
        }
        let strengths = peaks.map(\.strength).sorted()
        let threshold = strengths[strengths.count / 2] * 0.3
        let strong = peaks.filter { $0.strength > threshold }
        guard strong.count >= 4 else { return (phase, period) }

        // Least squares: frame = phase + beat * period.
        let n = Double(strong.count)
        let meanBeat = strong.map(\.beat).reduce(0, +) / n
        let meanFrame = strong.map(\.frame).reduce(0, +) / n
        let covariance = strong.map { ($0.beat - meanBeat) * ($0.frame - meanFrame) }.reduce(0, +)
        let variance = strong.map { pow($0.beat - meanBeat, 2) }.reduce(0, +)
        guard variance > 0 else { return (phase, period) }
        let fitted = covariance / variance
        // Keep the fit only if it's a small correction, not a different tempo.
        guard abs(fitted - period) < period * 0.05 else { return (phase, period) }
        var fittedPhase = meanFrame - fitted * meanBeat
        while fittedPhase < 0 { fittedPhase += fitted }
        return (fittedPhase, fitted)
    }

    /// Envelope value at a fractional frame, taking the peak of its neighbours
    /// so a beat a frame off still counts.
    private func strength(_ envelope: [Float], at frame: Double) -> Float {
        let i = Int(frame.rounded())
        return envelope[max(0, i - 1)...min(envelope.count - 1, i + 1)].max() ?? 0
    }

    /// Mean accent of the beats at `offset`, `offset + 4`, … (4/4 bars).
    private func barAccent(_ accents: [Float], offset: Int) -> Float {
        let picked = stride(from: offset, to: accents.count, by: 4).map { accents[$0] }
        return picked.isEmpty ? 0 : picked.reduce(0, +) / Float(picked.count)
    }
}
