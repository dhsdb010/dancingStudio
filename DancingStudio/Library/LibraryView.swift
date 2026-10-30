import SwiftData
import SwiftUI

/// The personal dance memory library: every analyzed routine, newest first.
struct LibraryView: View {
    @Query(sort: \SavedRoutine.createdAt, order: .reverse) private var routines: [SavedRoutine]
    @Environment(\.modelContext) private var modelContext
    @State private var renaming: SavedRoutine?
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            Group {
                if routines.isEmpty {
                    ContentUnavailableView("No routines yet", systemImage: "books.vertical",
                                           description: Text("Routines you import and analyze in Learn are saved here."))
                } else {
                    List {
                        ForEach(routines) { routine in
                            NavigationLink(value: routine) {
                                RoutineRow(routine: routine)
                            }
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") { startRenaming(routine) }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    RoutineStore.delete(routine, in: modelContext)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Rename", systemImage: "pencil") { startRenaming(routine) }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { RoutineStore.delete(routines[index], in: modelContext) }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: SavedRoutine.self) { routine in
                SavedRoutineView(routine: routine)
            }
            .alert("Rename routine", isPresented: .constant(renaming != nil)) {
                TextField("Name", text: $newTitle)
                Button("Save") {
                    let title = newTitle.trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty { renaming?.title = title }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }

    private func startRenaming(_ routine: SavedRoutine) {
        newTitle = routine.title
        renaming = routine
    }
}

private struct RoutineRow: View {
    let routine: SavedRoutine

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 48, height: 64)
                .clipShape(.rect(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(routine.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = routine.thumbnail, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "figure.dance")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary)
        }
    }

    private var details: String {
        var parts = [PrepareRoutineView.format(routine.duration)]
        if let bpm = routine.bpm { parts.append("\(Int(bpm.rounded())) BPM") }
        let n = routine.sectionCount
        parts.append(routine.sectionsArePhrases ? "\(n) phrase\(n == 1 ? "" : "s")" : "\(n) part\(n == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
}

/// Opens a saved routine in the step-by-step player.
private struct SavedRoutineView: View {
    let routine: SavedRoutine

    var body: some View {
        Group {
            if let analysis = try? routine.analysis(),
               FileManager.default.fileExists(atPath: routine.videoURL.path(percentEncoded: false)) {
                RoutinePlayerView(url: routine.videoURL, analysis: analysis, displaySize: routine.displaySize)
            } else {
                ContentUnavailableView("Can't open this routine", systemImage: "exclamationmark.triangle",
                                       description: Text("Its video or analysis is missing. Delete it and import the video again."))
            }
        }
        .navigationTitle(routine.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}
