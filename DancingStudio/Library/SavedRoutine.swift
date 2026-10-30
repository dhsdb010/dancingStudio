import AVFoundation
import Foundation
import SwiftData
import UIKit

/// A routine in the personal library: a copy of the video plus everything
/// analysis found, so it opens instantly without re-importing.
@Model
final class SavedRoutine {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    /// File name inside `RoutineStore.directory`.
    var videoFileName: String
    var displayWidth: Double
    var displayHeight: Double
    /// Length of the trimmed part, in seconds.
    var duration: Double
    var bpm: Double?
    var sectionCount: Int
    var sectionsArePhrases: Bool
    /// `RoutineAnalysis` as JSON.
    @Attribute(.externalStorage) var analysisData: Data
    @Attribute(.externalStorage) var thumbnail: Data?

    init(id: UUID, title: String, videoFileName: String, displaySize: CGSize,
         analysis: RoutineAnalysis, analysisData: Data, thumbnail: Data?) {
        self.id = id
        self.title = title
        self.createdAt = .now
        self.videoFileName = videoFileName
        self.displayWidth = displaySize.width
        self.displayHeight = displaySize.height
        self.duration = analysis.sequence.end - analysis.sequence.start
        self.bpm = analysis.beats?.bpm
        self.sectionCount = analysis.sections.count
        self.sectionsArePhrases = analysis.sectionsArePhrases
        self.analysisData = analysisData
        self.thumbnail = thumbnail
    }

    var displaySize: CGSize { CGSize(width: displayWidth, height: displayHeight) }
    var videoURL: URL { RoutineStore.directory.appending(path: videoFileName) }

    func analysis() throws -> RoutineAnalysis {
        try JSONDecoder().decode(RoutineAnalysis.self, from: analysisData)
    }
}

/// Saves and deletes library routines and their video files.
@MainActor
enum RoutineStore {
    /// Application Support/Routines. Kept out of Documents so the files
    /// aren't shown in the Files app.
    nonisolated static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Routines", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copies the video into the library and saves the analysis with it.
    @discardableResult
    static func save(video: URL, analysis: RoutineAnalysis, displaySize: CGSize,
                     title: String, in context: ModelContext) async throws -> SavedRoutine {
        let id = UUID()
        let fileName = "\(id.uuidString).\(video.pathExtension.isEmpty ? "mov" : video.pathExtension)"
        let destination = directory.appending(path: fileName)
        try FileManager.default.copyItem(at: video, to: destination)

        let routine = SavedRoutine(
            id: id,
            title: title,
            videoFileName: fileName,
            displaySize: displaySize,
            analysis: analysis,
            analysisData: try JSONEncoder().encode(analysis),
            thumbnail: await thumbnail(of: destination, at: analysis.sequence.start)
        )
        context.insert(routine)
        try context.save()
        return routine
    }

    static func delete(_ routine: SavedRoutine, in context: ModelContext) {
        try? FileManager.default.removeItem(at: routine.videoURL)
        context.delete(routine)
        try? context.save()
    }

    /// A small JPEG of the first frame of the trimmed part.
    private static func thumbnail(of video: URL, at time: TimeInterval) async -> Data? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)) else {
            return nil
        }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.7)
    }
}
