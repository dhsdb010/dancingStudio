import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A video chosen in the Photos picker, copied into the app's temporary folder
/// so it stays readable after the picker closes.
struct PickedVideo: Transferable, Hashable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appending(path: "\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedVideo(url: copy)
        }
    }
}
