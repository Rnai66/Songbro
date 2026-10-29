import Foundation

/// One beat on the BeatBuddy, numbered as BBManager shows it (1-based).
struct Beat: Codable, Hashable {
    var number: Int
    var name: String
}

/// One folder on the BeatBuddy SD card, numbered as BBManager shows it (1-based).
struct BeatFolder: Codable, Hashable, Identifiable {
    var number: Int
    var name: String
    var beats: [Beat]
    var id: Int { number }
}

/// One drum set (kit sound) on the BeatBuddy SD card, numbered as BBManager shows it.
struct DrumSet: Codable, Hashable, Identifiable {
    var number: Int
    var name: String
    var id: Int { number }
}

/// Beats exported from a BBManager project by tools/make_beats.py.
struct BeatCatalog: Codable {
    var project: String
    var folders: [BeatFolder]
    var drumSets: [DrumSet]? = nil

    static let bundled: BeatCatalog = {
        guard let url = Bundle.main.url(forResource: "beats", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(BeatCatalog.self, from: data)
        else { return BeatCatalog(project: "-", folders: []) }
        return catalog
    }()

    func folder(_ number: Int) -> BeatFolder? {
        folders.first { $0.number == number }
    }

    func drumSetName(_ number: Int?) -> String? {
        guard let number else { return nil }
        return drumSets?.first { $0.number == number }?.name ?? "Drum Set \(number)"
    }

    /// "Thai Style › Morlum 1", or nil when the song has no beat.
    func label(folder: Int?, beat: Int?) -> String? {
        guard let folder, let beat, let f = self.folder(folder) else { return nil }
        let beatName = f.beats.first { $0.number == beat }?.name ?? "#\(beat)"
        return "\(f.name) › \(beatName)"
    }
}

struct Song: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var artist = ""
    var category = "ทั่วไป"
    var key = ""
    var bpm = 100
    /// BeatBuddy folder/beat numbers (1-based, as in BBManager).
    var beatFolder: Int?
    var beatNumber: Int?
    /// BeatBuddy drum set (kit sound), 1-based as in BBManager; nil = keep the current one.
    var drumSet: Int?
    /// NUX Dual Loop Stereo phrase memory 01–99.
    var nuxMemory: Int?
    /// Lyrics with chords in ChordPro style: "[C]คำร้อง [G]ต่อไป".
    var lyrics = ""
    /// Lyric sheet image, relative to the FolderLibrary root (nil = typed lyrics).
    var filePath: String?
    /// Beat/BPM were filled in automatically and not checked yet (shown as "≈").
    var estimated: Bool?
    /// Musical style found by the AI beat search ("ลูกทุ่ง", "Pop Rock").
    var style: String?

    /// "Thai Style › Morlum 1" for BeatBuddy, "Memory 07" for NUX, nil if not set.
    func rhythmLabel(for device: StageDevice) -> String? {
        let label: String? = switch device {
        case .beatBuddy: BeatCatalog.bundled.label(folder: beatFolder, beat: beatNumber)
        case .nuxDualLoop: nuxMemory.map { String(format: "Memory %02d", $0) }
        }
        return label.map { estimated == true ? "≈ " + $0 : $0 }
    }
}
