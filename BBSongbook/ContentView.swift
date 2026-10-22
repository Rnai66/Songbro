import SwiftUI

/// Three columns like the songbook app: categories | songs | lyrics.
struct ContentView: View {
    /// Back to the SongBro home screen.
    var onHome: () -> Void = {}

    @Environment(SongStore.self) private var store
    @Environment(StageMIDI.self) private var midi
    @Environment(FolderLibrary.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var pickingFolder = false

    /// "" = all songs.
    @State private var category: String? = ""
    @State private var selectedID: Song.ID?
    @State private var search = ""
    @State private var editing: Song?
    @State private var showMIDI = false

    private var songs: [Song] {
        store.songs(in: category?.isEmpty == false ? category : nil)
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                || $0.artist.localizedCaseInsensitiveContains(search)
                || $0.category.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $category) {
                Label("ทุกเพลง", systemImage: "music.note.list").tag("")
                Section("หมวด") {
                    ForEach(store.categories, id: \.self) { name in
                        Label(name, systemImage: "folder.fill").tag(name)
                    }
                }
                Section {
                    Label(library.rootName, systemImage: "externaldrive.connected.to.line.below")
                        .foregroundStyle(.secondary)
                    Button("เลือกโฟลเดอร์เพลง…", systemImage: "folder.badge.plus") { pickingFolder = true }
                    Button("อัปเดตรายการเพลง", systemImage: "arrow.clockwise", action: refreshLibrary)
                    if library.isLinked {
                        Button("เลิกเชื่อมโฟลเดอร์", systemImage: "xmark.circle", role: .destructive) {
                            library.unlink()
                            refreshLibrary()
                        }
                    }
                } header: {
                    Text("โฟลเดอร์เพลง (รูป .png / .jpg)")
                } footer: {
                    Text("โฟลเดอร์ย่อยกลายเป็นหมวด รูปแต่ละรูปคือหนึ่งเพลง")
                }
            }
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    library.link(url)
                    category = ""
                    refreshLibrary()
                }
            }
            .navigationTitle("SongBro")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("หน้าแรก", systemImage: "house", action: onHome)
                }
                ToolbarItem {
                    Button { showMIDI = true } label: {
                        Label(midi.active.shortName,
                              systemImage: midi.isConnected ? "cable.connector" : "cable.connector.slash")
                    }
                    .tint(midi.isConnected ? .green : .secondary)
                }
            }
        } content: {
            List(selection: $selectedID) {
                if store.availableFiles.isEmpty {
                    Section { importHelp }
                }
                ForEach(songs) { song in
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text(song.title).font(.headline)
                    } icon: {
                        Image(systemName: song.filePath == nil ? "text.quote" : "photo")
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        if !song.key.isEmpty { Text("คีย์ \(song.key)") }
                        Text("\(song.bpm) BPM")
                        if let rhythm = song.rhythmLabel(for: midi.active) {
                            Text(rhythm).lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button("แก้ไข", systemImage: "pencil") { editing = song }
                    Button("ลบ", systemImage: "trash", role: .destructive) { store.delete(song) }
                }
                }
            }
            .searchable(text: $search, prompt: "ค้นหาเพลง")
            .navigationTitle(category?.isEmpty == false ? category! : "ทุกเพลง")
            .toolbar {
                Button {
                    var song = Song(title: "")
                    if let category, !category.isEmpty { song.category = category }
                    editing = song
                } label: { Label("เพิ่มเพลง", systemImage: "plus") }
            }
        } detail: {
            if let id = selectedID, let song = store.songs.first(where: { $0.id == id }) {
                PerformanceView(song: song,
                                setSongs: songs,
                                onEdit: { editing = song },
                                onOpen: { selectedID = $0.id })
                    .id(song.id)
            } else {
                ContentUnavailableView("เลือกเพลง", systemImage: "music.mic",
                                       description: Text("แตะเพลงทางซ้ายเพื่อเปิดเนื้อเพลง"))
            }
        }
        .sheet(item: $editing) { song in
            SongEditorView(song: song)
                .pageSizedSheet()
        }
        .sheet(isPresented: $showMIDI) {
            MIDISettingsView()
        }
        // Pick up sheets added in the Files app while we were in the background.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { refreshLibrary() }
        }
        // A sheet sent from another app ("Open in / Share › BB Songbook").
        .onOpenURL { url in
            guard let file = library.importFile(url) else { return }
            refreshLibrary()
            category = FolderLibrary.importFolder
            selectedID = store.songs.first { $0.filePath == file.path }?.id
        }
    }

    /// Shown until the first lyric sheet image is in the library.
    private var importHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ยังไม่มีรูปเนื้อเพลงในแอป", systemImage: "photo.on.rectangle.angled")
                .font(.headline)
            Text("แอปอื่นซ่อนไฟล์ไว้ในตัวเอง BB Songbook จึงค้นหาเองไม่ได้ ต้องส่งไฟล์เข้ามาด้วยวิธีใดวิธีหนึ่ง:")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("1. ใน File Manager เปิดรูปเพลง › ปุ่มแชร์ › เลือก **BB Songbook**")
                Text("2. Mac › Finder › iPad › แท็บ **ไฟล์** › ลากโฟลเดอร์เพลงไปวางที่ **BB Songbook**")
                Text("3. ถ้าย้ายไว้ในแอป \"ไฟล์\" แล้ว กดปุ่มด้านล่าง")
            }
            .font(.subheadline)
            Button("เลือกโฟลเดอร์เพลง…", systemImage: "folder.badge.plus") { pickingFolder = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
        .selectionDisabled()
    }

    private func refreshLibrary() {
        if let files = library.scan() { store.sync(files) }
    }
}
