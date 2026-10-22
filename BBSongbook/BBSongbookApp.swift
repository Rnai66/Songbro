import SwiftUI

@main
struct BBSongbookApp: App {
    @State private var store = SongStore()
    @State private var midi = StageMIDI()
    @State private var library = FolderLibrary()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(midi)
                .environment(library)
        }
    }
}
