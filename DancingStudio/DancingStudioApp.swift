import SwiftData
import SwiftUI

@main
struct DancingStudioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SavedRoutine.self)
    }
}
