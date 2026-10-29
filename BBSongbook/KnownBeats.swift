import Foundation

/// The user's own beat tables ("Drummer Song", "Drumesong2"), bundled from
/// tools/build_known_beats.py. New songs whose name is in the list get that
/// BeatBuddy beat and BPM straight away.
struct KnownBeats {
    struct Entry: Decodable {
        var title: String
        var folder: Int
        var beat: Int
        var bpm: Int?
        var source: String
    }

    static let bundled = KnownBeats()

    private var exact: [String: Entry] = [:]
    /// Longer names first, so "ขอใจเธอคืนกลับมา" prefers the most specific match.
    private var prefixes: [(key: String, entry: Entry)] = []

    private init() {
        guard let url = Bundle.main.url(forResource: "known_beats", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        for entry in entries {
            exact[Self.normalize(entry.title)] = entry
        }
        prefixes = exact.map { (key: $0.key, entry: $0.value) }
            .filter { $0.key.count >= 5 }
            .sorted { $0.key.count > $1.key.count }
    }

    /// A spread of the user's own picks, used to show the AI how they choose beats.
    func examples(limit: Int) -> [Entry] {
        let all = exact.values.sorted { $0.title < $1.title }
        guard all.count > limit else { return all }
        let step = Double(all.count) / Double(limit)
        return (0..<limit).map { all[Int(Double($0) * step)] }
    }

    /// The table row for a song file name like "6-สบายสบาย-เบิร์ด" or "Fly Me To The Moon-Dm".
    func lookup(_ title: String) -> Entry? {
        let key = Self.normalize(title)
        if let hit = exact[key] { return hit }
        // File names often add the artist or a key: "ซ่อนกลิ่น-ปาลมมี่".
        return prefixes.first { key.hasPrefix($0.key) }?.entry
    }

    /// Drops a leading set number ("2-", "9_") and spaces/punctuation, lowercased.
    static func normalize(_ title: String) -> String {
        var t = title.replacingOccurrences(of: #"^\d+[-_ ]*"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[\s\-_.'’&]"#, with: "", options: .regularExpression)
        return t.lowercased()
    }
}
