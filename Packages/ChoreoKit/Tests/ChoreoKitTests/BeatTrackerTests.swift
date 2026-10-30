import AVFoundation
import Foundation
import Testing
@testable import ChoreoKit

/// A click track: short noise bursts on every beat, with every 4th beat
/// (starting at `downbeat`) twice as loud, like a kick on the "1".
private func clickTrack(bpm: Double, seconds: Double, firstBeat: Double = 0.25, downbeat: Int = 0,
                        sampleRate: Double = AudioLoader.sampleRate) -> (samples: [Float], beats: [Double]) {
    var samples = [Float](repeating: 0, count: Int(seconds * sampleRate))
    var seed: UInt32 = 1
    func noise() -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(seed >> 8) / Float(1 << 24) * 2 - 1
    }
    var beats: [Double] = []
    var t = firstBeat
    while t < seconds - 0.05 {
        let loud: Float = (beats.count - downbeat) % 4 == 0 ? 1 : 0.5
        let start = Int(t * sampleRate)
        for i in 0..<Int(0.03 * sampleRate) where start + i < samples.count {
            samples[start + i] = loud * noise() * exp(-Float(i) / Float(0.005 * sampleRate))
        }
        beats.append(t)
        t += 60 / bpm
    }
    return (samples, beats)
}

private func expectBeats(_ grid: BeatGrid, near truth: [Double], tolerance: Double = 0.015) {
    // Every detected beat is close to a real one.
    for beat in grid.beats {
        let nearest = truth.min { abs($0 - beat) < abs($1 - beat) }!
        #expect(abs(nearest - beat) < tolerance, "beat at \(beat) is \(nearest - beat) s off")
    }
}

@Test(arguments: [95.0, 120.0, 128.0, 150.0])
func findsTheTempoOfAClickTrack(bpm: Double) throws {
    let track = clickTrack(bpm: bpm, seconds: 20)
    let grid = try #require(BeatTracker().track(samples: track.samples, sampleRate: AudioLoader.sampleRate))
    #expect(abs(grid.bpm - bpm) < 1.5)
    expectBeats(grid, near: track.beats)
}

@Test func findsTheAccentedDownbeat() throws {
    let track = clickTrack(bpm: 120, seconds: 20, downbeat: 2)
    let grid = try #require(BeatTracker().track(samples: track.samples, sampleRate: AudioLoader.sampleRate))
    let downbeat = grid.beats[grid.firstDownbeat]
    let truthIndex = track.beats.firstIndex { abs($0 - downbeat) < 0.03 }
    #expect(truthIndex.map { ($0 - 2) % 4 == 0 } == true)
}

@Test func offsetsBeatsByTheStartTime() throws {
    let track = clickTrack(bpm: 120, seconds: 12)
    let grid = try #require(BeatTracker().track(samples: track.samples, sampleRate: AudioLoader.sampleRate, startTime: 30))
    expectBeats(grid, near: track.beats.map { $0 + 30 })
}

@Test func silenceHasNoBeat() {
    let silence = [Float](repeating: 0, count: Int(10 * AudioLoader.sampleRate))
    #expect(BeatTracker().track(samples: silence, sampleRate: AudioLoader.sampleRate) == nil)
}

@Test func tooShortForABeat() {
    let track = clickTrack(bpm: 120, seconds: 1)
    #expect(BeatTracker().track(samples: track.samples, sampleRate: AudioLoader.sampleRate) == nil)
}

@Test func countsOneToEightFromTheDownbeat() {
    let grid = BeatGrid(bpm: 120, beats: stride(from: 0.0, to: 10, by: 0.5).map { $0 }, firstDownbeat: 2)
    #expect(grid.count(at: -0.2) == 6)    // just before the first beat
    #expect(grid.count(at: -2) == nil)    // well before the beats
    #expect(grid.count(at: 0.1) == 7)     // pickup: "7, 8, 1"
    #expect(grid.count(at: 0.6) == 8)
    #expect(grid.count(at: 1.1) == 1)
    #expect(grid.count(at: 1.6) == 2)
    #expect(grid.count(at: 4.6) == 8)
    #expect(grid.count(at: 5.1) == 1)
    #expect(grid.count(at: 30) == nil)    // long after the last beat
}

@Test func loadsAndTracksAudioFromAFile() async throws {
    let track = clickTrack(bpm: 120, seconds: 12, sampleRate: 44_100)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).caf")
    defer { try? FileManager.default.removeItem(at: url) }
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    do {
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(track.samples.count))!
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            track.samples.withUnsafeBufferPointer { buffer.floatChannelData![channel].update(from: $0.baseAddress!, count: $0.count) }
        }
        try file.write(from: buffer)
    }

    let samples = try #require(try await AudioLoader.samples(from: url, start: 2, end: 10))
    #expect(abs(Double(samples.count) / AudioLoader.sampleRate - 8) < 0.05)
    let grid = try #require(BeatTracker().track(samples: samples, sampleRate: AudioLoader.sampleRate, startTime: 2))
    #expect(abs(grid.bpm - 120) < 1.5)
    expectBeats(grid, near: track.beats)
}

@Test func slicesIntoWholeEightCountPhrases() {
    let grid = BeatGrid(bpm: 120, beats: stride(from: 0.1, to: 20, by: 0.5).map { $0 }, firstDownbeat: 1)
    let sections = Sectioner.eightCounts(grid, start: 0, end: 20)
    // Each phrase runs "1" to "1": the 0.6 s pickup and the 3.4 s tail are
    // left out of the sections.
    #expect(sections.map(\.start) == [0.6, 4.6, 8.6, 12.6])
    #expect(sections.map(\.end) == [4.6, 8.6, 12.6, 16.6])
    #expect(sections.map(\.index) == [0, 1, 2, 3])
}

@Test func phrasesStartOnTheOneAfterAPickup() {
    // Three beats (1.5 s) before the first "1".
    let grid = BeatGrid(bpm: 120, beats: stride(from: 0.0, to: 20, by: 0.5).map { $0 }, firstDownbeat: 3)
    let sections = Sectioner.eightCounts(grid, start: 0, end: 20)
    #expect(sections.map(\.start) == [1.5, 5.5, 9.5, 13.5])
    #expect(sections.allSatisfy { abs($0.duration - 4) < 1e-9 })
}

@Test func aPhraseEndingAtTheTrimPointCounts() {
    // The grid stops one beat short of the last "1", so its end is extrapolated.
    let grid = BeatGrid(bpm: 120, beats: stride(from: 0.0, to: 7.6, by: 0.5).map { $0 }, firstDownbeat: 0)
    let sections = Sectioner.eightCounts(grid, start: 0, end: 8)
    #expect(sections.map(\.end) == [4, 8])
}

@Test func tooShortForAPhraseHasNoSections() {
    let grid = BeatGrid(bpm: 120, beats: stride(from: 0.0, to: 3, by: 0.5).map { $0 }, firstDownbeat: 0)
    #expect(Sectioner.eightCounts(grid, start: 0, end: 3).isEmpty)
}

@Test func fixedLengthSectionsCoverTheRoutine() {
    let sections = Sectioner.fixedLength(start: 1, end: 11)
    #expect(sections.count == 3 || sections.count == 2)
    #expect(sections.first?.start == 1)
    #expect(sections.last?.end == 11)
    #expect(zip(sections, sections.dropFirst()).allSatisfy { $0.end == $1.start })
}
