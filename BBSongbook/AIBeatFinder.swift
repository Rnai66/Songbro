import Foundation
import Observation
import Security

/// Asks Google Gemini (with Google Search grounding) for a song's tempo, style and
/// the closest beat in the user's BeatBuddy catalog. Results are saved as
/// estimates (≈) so the user still checks them by ear.
@Observable
final class AIBeatFinder {
    struct Suggestion: Equatable {
        var bpm: Int?
        var style: String
        var timeSignature: String
        var folder: Int?
        var beat: Int?
        var drumSet: Int?
        var artist: String
        var key: String
        var confidence: String
        var note: String
    }

    enum FinderError: LocalizedError {
        case noKey, http(Int, String), badReply

        var errorDescription: String? {
            switch self {
            case .noKey: "ยังไม่ได้ใส่ Gemini API key (หน้าแรก › AI ค้นหาจังหวะ)"
            case .http(let code, let message): "Gemini ตอบ \(code): \(message)"
            case .badReply: "อ่านคำตอบจาก Gemini ไม่ได้ ลองใหม่อีกครั้ง"
            }
        }
    }

    var apiKey: String {
        didSet { Keychain.save(apiKey, account: Self.keyAccount) }
    }
    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Self.modelKey) }
    }
    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    /// "Find all" progress, shown above the song list.
    private(set) var batchRunning = false
    private(set) var batchDone = 0
    private(set) var batchTotal = 0
    private(set) var batchCurrent = ""
    var batchError: String?
    private var batchTask: Task<Void, Never>?

    static let defaultModel = "gemini-flash-latest"
    private static let keyAccount = "gemini.apiKey"
    private static let modelKey = "ai.geminiModel"

    init() {
        apiKey = Keychain.load(account: Self.keyAccount) ?? ""
        model = UserDefaults.standard.string(forKey: Self.modelKey) ?? Self.defaultModel
    }

    // MARK: - One song

    func suggest(for song: Song) async throws -> Suggestion {
        let reply = try await generate(prompt: Self.prompt(for: song), search: true)
        guard let suggestion = Self.parse(reply) else { throw FinderError.badReply }
        return suggestion
    }

    /// Writes a suggestion into the song, marked ≈ until the user checks it.
    static func apply(_ s: Suggestion, to song: inout Song) {
        if let bpm = s.bpm { song.bpm = min(max(bpm, 40), 300) }
        if let folder = s.folder, let beat = s.beat {
            song.beatFolder = folder
            song.beatNumber = beat
        }
        if let kit = s.drumSet { song.drumSet = kit }
        if song.key.isEmpty, !s.key.isEmpty { song.key = s.key }
        if song.artist.isEmpty, !s.artist.isEmpty { song.artist = s.artist }
        if !s.style.isEmpty { song.style = s.style }
        song.estimated = true
    }

    /// Short call to check the key and model name.
    func testKey() async throws -> String {
        try await generate(prompt: "Reply with the single word OK.", search: false)
    }

    // MARK: - Many songs

    /// Looks up every given song one by one, saving each result as it arrives.
    func findAll(_ songs: [Song], in store: SongStore) {
        guard !batchRunning, !songs.isEmpty else { return }
        batchRunning = true
        batchDone = 0
        batchTotal = songs.count
        batchError = nil
        batchTask = Task { @MainActor in
            for song in songs {
                if Task.isCancelled { break }
                batchCurrent = song.title
                do {
                    let s = try await suggest(for: song)
                    if var latest = store.songs.first(where: { $0.id == song.id }),
                       latest.beatFolder == nil || latest.estimated == true {
                        Self.apply(s, to: &latest)
                        store.upsert(latest)
                    }
                } catch FinderError.http(let code, let message) where code == 429 {
                    // Free-tier rate limit: wait and try this song once more.
                    try? await Task.sleep(for: .seconds(30))
                    if let s = try? await suggest(for: song),
                       var latest = store.songs.first(where: { $0.id == song.id }) {
                        Self.apply(s, to: &latest)
                        store.upsert(latest)
                    } else {
                        batchError = "Gemini ตอบ 429: \(message)"
                        break
                    }
                } catch {
                    if Task.isCancelled { break }
                    batchError = error.localizedDescription
                    break
                }
                batchDone += 1
                // Stay under the free tier's requests-per-minute limit.
                try? await Task.sleep(for: .seconds(4))
            }
            batchRunning = false
            batchCurrent = ""
        }
    }

    func cancelBatch() {
        batchTask?.cancel()
        batchRunning = false
        batchCurrent = ""
    }

    // MARK: - Gemini API

    private func generate(prompt: String, search: Bool) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw FinderError.noKey }
        let name = model.trimmingCharacters(in: .whitespaces).isEmpty ? Self.defaultModel : model
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(name):generateContent")!
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        var body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.2],
        ]
        if search { body["tools"] = [["google_search": [String: Any]()]] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? ""
            throw FinderError.http(http.statusCode, message)
        }
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { throw FinderError.badReply }
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    // MARK: - Prompt

    private static func prompt(for song: Song) -> String {
        """
        You help a Thai live musician set up a BeatBuddy drum pedal for each song.
        Song file name: "\(song.title)"
        Folder in the songbook: "\(song.category)"
        \(song.artist.isEmpty ? "" : "Artist: \(song.artist)\n")\
        The file name may start with a set number ("6-") and end with the artist or key ("-เบิร์ด", "-Dm").

        Search the web for this song's original recording and find its tempo (BPM), \
        time signature, musical style (for Thai songs e.g. ลูกทุ่ง, ลูกกรุง, หมอลำ, สามช่า, \
        ร็อค, ป๊อป, เพื่อชีวิต, เร็กเก้, บัลลาด) and original key.
        Then choose the ONE beat from the catalog below that a drummer would play for it, \
        and a drum set (kit sound) that suits it.

        BeatBuddy beats — "folder.beat name":
        \(catalogText)

        Drum sets — "number name":
        \(drumSetText)

        Examples of how this musician chooses beats for songs they already set:
        \(examplesText)

        Answer with ONLY one JSON object, no other text:
        {"bpm": 120, "timeSignature": "4/4", "style": "ลูกทุ่ง", "folder": 28, "beat": 3, \
        "drumSet": 8, "artist": "ชื่อศิลปิน", "key": "Am", \
        "confidence": "high|medium|low", "note": "เหตุผลสั้นๆ ภาษาไทย"}
        Use null for anything you cannot find. folder and beat must be a pair from the catalog.
        """
    }

    /// Catalog lines, skipping metronome/test folders.
    private static let catalogText: String = {
        let skip: Set<String> = ["Metronome", "Test Beats"]
        return BeatCatalog.bundled.folders
            .filter { !$0.beats.isEmpty && !skip.contains($0.name) }
            .map { folder in
                "\(folder.name): " + folder.beats.map { "\(folder.number).\($0.number) \($0.name)" }
                    .joined(separator: " | ")
            }
            .joined(separator: "\n")
    }()

    private static let drumSetText: String = {
        (BeatCatalog.bundled.drumSets ?? []).map { "\($0.number) \($0.name)" }.joined(separator: ", ")
    }()

    private static let examplesText: String = {
        KnownBeats.bundled.examples(limit: 40).map { e in
            "\(e.title) → \(e.folder).\(e.beat)" + (e.bpm.map { " \($0) BPM" } ?? "")
        }.joined(separator: "\n")
    }()

    // MARK: - Reply

    static func parse(_ text: String) -> Suggestion? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func int(_ k: String) -> Int? {
            if let n = obj[k] as? NSNumber { return n.intValue }
            if let s = obj[k] as? String { return Int(s.filter(\.isNumber)) }
            return nil
        }
        func str(_ k: String) -> String { (obj[k] as? String)?.trimmingCharacters(in: .whitespaces) ?? "" }

        let catalog = BeatCatalog.bundled
        var folder = int("folder"), beat = int("beat")
        // Only keep a beat that really exists on the user's SD card.
        let beatExists = folder.flatMap { catalog.folder($0) }?.beats.contains { $0.number == beat } ?? false
        if !beatExists { folder = nil; beat = nil }
        var kit = int("drumSet")
        if let k = kit, catalog.drumSets?.contains(where: { $0.number == k }) != true { kit = nil }
        var bpm = int("bpm")
        if let b = bpm, !(40...300).contains(b) { bpm = nil }

        return Suggestion(bpm: bpm, style: str("style"), timeSignature: str("timeSignature"),
                          folder: folder, beat: beat, drumSet: kit, artist: str("artist"),
                          key: str("key"), confidence: str("confidence"), note: str("note"))
    }
}

/// Minimal Keychain wrapper for the API key (never stored in the repo or UserDefaults).
enum Keychain {
    private static let service = "com.rnai66.bbsongbook"

    static func save(_ value: String, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
