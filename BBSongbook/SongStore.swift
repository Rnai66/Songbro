import Foundation
import Observation

/// Songs saved as JSON in the app's Documents folder (visible in the Files app).
@Observable
final class SongStore {
    var songs: [Song] = [] {
        didSet { save() }
    }

    private let fileURL = URL.documentsDirectory.appending(path: "songs.json")

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Song].self, from: data) {
            songs = saved
        } else {
            songs = Self.samples
        }
    }

    /// Image paths present in the song folder right now. Songs whose image is
    /// missing are hidden, not deleted, so their beat/BPM come back with the file.
    var availableFiles: Set<String> = []

    private var visibleSongs: [Song] {
        songs.filter { $0.filePath.map(availableFiles.contains) ?? true }
    }

    var categories: [String] {
        Array(Set(visibleSongs.map(\.category))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func songs(in category: String?) -> [Song] {
        visibleSongs.filter { category == nil || $0.category == category }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Add a song for every new sheet in the folder; the folder decides the category.
    func sync(_ files: [LibraryFile]) {
        availableFiles = Set(files.map(\.path))
        var updated = songs
        let indexByPath = Dictionary(
            updated.enumerated().compactMap { i, song in song.filePath.map { ($0, i) } },
            uniquingKeysWith: { first, _ in first })
        for file in files {
            if let i = indexByPath[file.path] {
                updated[i].category = file.category
            } else {
                updated.append(Song(title: file.title, category: file.category, filePath: file.path))
            }
        }
        for i in updated.indices {
            Self.applyKnownBeat(to: &updated[i])
        }
        if updated != songs { songs = updated }
    }

    /// Songs in the user's beat tables get that beat and BPM. Only songs with no
    /// beat yet, or with an unchecked estimate (≈), are touched — never a song
    /// the user has set or edited.
    private static func applyKnownBeat(to song: inout Song) {
        guard song.beatFolder == nil || song.estimated == true,
              let known = KnownBeats.bundled.lookup(song.title) else { return }
        song.beatFolder = known.folder
        song.beatNumber = known.beat
        if let bpm = known.bpm { song.bpm = bpm }
        song.estimated = nil
    }

    func upsert(_ song: Song) {
        if let i = songs.firstIndex(where: { $0.id == song.id }) {
            songs[i] = song
        } else {
            songs.append(song)
        }
    }

    func delete(_ song: Song) {
        songs.removeAll { $0.id == song.id }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(songs).write(to: fileURL, options: .atomic)
    }

    /// Placeholder songs (original text) so the prototype has something to show.
    static let samples: [Song] = [
        Song(title: "ตัวอย่าง หมอลำ", category: "สากลแยก", key: "Am", bpm: 140,
             beatFolder: 28, beatNumber: 2,
             lyrics: """
             {ท่อน 1}
             [Am]ทดสอบเนื้อร้อง บรรทัด[G]แรก
             [F]จังหวะหมอลำ ดัง[E]แทรก
             [Am]เหยียบเปลี่ยนท่อน ได้[G]ทันใจ
             [F]เนื้อเลื่อนตาม [E]ไป

             {ฮุก}
             [C]ร้องพร้อมกัน [G]ให้ดังดัง
             [Am]มือปรบตาม [E]จังหวะกลอง
             """),
        Song(title: "ตัวอย่าง เพลงช้า", category: "เพลงช้า", key: "C", bpm: 72,
             beatFolder: 1, beatNumber: 1,
             lyrics: """
             {ท่อน 1}
             [C]นี่คือเพลง[Am]ตัวอย่าง
             [F]เอาไว้ทด[G]สอบแอป
             [C]คอร์ดอยู่[Am]ด้านบน
             [F]เนื้อร้อง[G]อยู่ด้านล่าง[C]

             {ฮุก}
             [F]ใส่เนื้อเพลง[G]ของเราเอง
             [Em]แทนบรรทัด[Am]เหล่านี้
             [Dm]ได้ในหน้า[G]แก้ไข[C]
             """),
        Song(title: "ตัวอย่าง ไทยป๊อป", category: "สากล", key: "G", bpm: 118,
             beatFolder: 28, beatNumber: 7,
             lyrics: """
             [G]บรรทัดหนึ่ง [D]บรรทัดสอง
             [Em]ลองเลื่อน[C]ดู
             [G]กดเริ่ม แล้ว [D]BeatBuddy
             [C]จะตี[D]กลองให้[G]เรา
             """),
    ]
}
