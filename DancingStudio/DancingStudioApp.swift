import AVFoundation
import SwiftData
import SwiftUI

@main
struct DancingStudioApp: App {
    init() {
        // Play routine music even with the silent switch on. Set once, off
        // the main thread: changing the session category can block.
        Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedRoutine.self)
    }
}
