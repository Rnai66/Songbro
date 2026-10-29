import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct SongEditorView: View {
    @State var song: Song

    @Environment(SongStore.self) private var store
    @Environment(StageMIDI.self) private var midi
    @Environment(FolderLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var importingImage = false
    @State private var photo: PhotosPickerItem?
    @State private var importError: String?
    /// Image copied in while editing; removed again if the user cancels.
    @State private var importedPath: String?

    private let catalog = BeatCatalog.bundled

    var body: some View {
        NavigationStack {
            Form {
                Section("เพลง") {
                    TextField("ชื่อเพลง", text: $song.title)
                    TextField("ศิลปิน", text: $song.artist)
                    TextField("หมวด (เช่น เพลงช้า, สากล)", text: $song.category)
                    TextField("คีย์ (เช่น C, Am)", text: $song.key)
                        .textInputAutocapitalization(.never)
                }

                Section("BeatBuddy · โปรเจกต์ \(catalog.project)") {
                    Picker("โฟลเดอร์จังหวะ", selection: folderBinding) {
                        Text("ไม่ใช้กลอง").tag(Int?.none)
                        ForEach(catalog.folders.filter { !$0.beats.isEmpty }) { folder in
                            Text("\(folder.number). \(folder.name)").tag(Int?.some(folder.number))
                        }
                    }
                    if let folder = song.beatFolder.flatMap(catalog.folder) {
                        Picker("จังหวะ", selection: $song.beatNumber) {
                            ForEach(folder.beats, id: \.number) { beat in
                                Text("\(beat.number). \(beat.name)").tag(Int?.some(beat.number))
                            }
                        }
                    }
                    Stepper("BPM \(song.bpm)", value: $song.bpm, in: 40...300)
                    Button("ลองส่งไป BeatBuddy", systemImage: "paperplane") { midi.load(song) }
                }

                if let path = song.filePath {
                    Section("ไฟล์เนื้อเพลง (รูป)") {
                        Label(path, systemImage: "photo")
                        Text("ชื่อและจังหวะที่ตั้งตรงนี้เก็บไว้ในแอป ไฟล์รูปต้นฉบับไม่ถูกแก้")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                Section {
                    Button("เลือกไฟล์รูป (.png / .jpg / .heic)", systemImage: "folder") { importingImage = true }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("เลือกจากแอปรูปภาพ", systemImage: "photo.on.rectangle")
                    }
                    if let importError {
                        Text(importError).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("รูปเนื้อเพลง")
                } footer: {
                    Text("รูปจะถูกคัดลอกเข้าโฟลเดอร์ของหมวด \"\(song.category)\" ในแอป · ถ้าใช้รูปแล้วไม่ต้องพิมพ์เนื้อเพลงด้านล่าง")
                }

                Section {
                    TextEditor(text: $song.lyrics)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 320)
                } header: {
                    HStack {
                        Text("เนื้อเพลง")
                        Spacer()
                        Button("นำเข้าไฟล์ .txt", systemImage: "square.and.arrow.down") { importing = true }
                            .font(.caption)
                    }
                } footer: {
                    Text("ใส่คอร์ดในวงเล็บเหลี่ยม เช่น [C]คำร้อง [G]ต่อไป  ·  หัวท่อนใช้ {ท่อน 1} หรือ {ฮุก}")
                }
                }
            }
            .navigationTitle(song.title.isEmpty ? "เพลงใหม่" : song.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") {
                        if let importedPath {
                            try? FileManager.default.removeItem(at: library.rootURL.appending(path: importedPath))
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") {
                        if song.title.isEmpty { song.title = "เพลงไม่มีชื่อ" }
                        song.estimated = nil
                        store.upsert(song)
                        dismiss()
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    song.lyrics = text
                    if song.title.isEmpty { song.title = url.deletingPathExtension().lastPathComponent }
                }
            }
            .background {
                // A second importer on the same view would replace the first one.
                Color.clear.fileImporter(isPresented: $importingImage, allowedContentTypes: [.image]) { result in
                    guard case .success(let url) = result else { return }
                    attach(library.importFile(url, into: categoryForImport))
                }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    let name = song.title.isEmpty
                        ? "รูป " + Date.now.formatted(.dateTime.year().month().day().hour().minute())
                        : song.title
                    attach(data.flatMap { library.importImage($0, name: name, ext: ext, into: categoryForImport) })
                    photo = nil
                }
            }
        }
    }

    private var categoryForImport: String {
        let c = song.category.trimmingCharacters(in: .whitespaces)
        return c.isEmpty || c == "ทั่วไป" ? FolderLibrary.importFolder : c
    }

    /// The song now shows the imported image instead of typed lyrics.
    private func attach(_ file: LibraryFile?) {
        guard let file else {
            importError = "นำเข้ารูปไม่ได้ ลองเลือกใหม่อีกครั้ง"
            return
        }
        importError = nil
        importedPath = file.path
        song.filePath = file.path
        song.category = file.category
        if song.title.isEmpty { song.title = file.title }
    }

    /// Picking a beat folder resets the beat to that folder's first beat.
    private var folderBinding: Binding<Int?> {
        Binding {
            song.beatFolder
        } set: { newFolder in
            song.beatFolder = newFolder
            song.beatNumber = newFolder.flatMap(catalog.folder)?.beats.first?.number
        }
    }
}

extension View {
    /// Tall sheet on iPad so every editor field fits without scrolling (iOS 18+).
    @ViewBuilder
    func pageSizedSheet() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }
}
