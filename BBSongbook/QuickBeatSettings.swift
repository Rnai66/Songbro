import SwiftUI

/// Popover from the chips above the lyrics: pick the BeatBuddy beat or NUX memory, BPM and key
/// without opening the full editor. Every change is saved and sent at once.
struct QuickBeatSettings: View {
    let song: Song

    @Environment(SongStore.self) private var store
    @Environment(StageMIDI.self) private var midi
    @Environment(AIBeatFinder.self) private var ai
    @Environment(\.dismiss) private var dismiss
    @State private var aiSuggestion: AIBeatFinder.Suggestion?
    @State private var aiSearching = false
    @State private var aiError: String?

    private let catalog = BeatCatalog.bundled

    var body: some View {
        NavigationStack {
            Form {
                aiSection

                Section("BPM") {
                    HStack {
                        Text("\(song.bpm)")
                            .font(.title.monospacedDigit().bold())
                        Spacer()
                        ForEach([-5, -1, 1, 5], id: \.self) { step in
                            Button(step > 0 ? "+\(step)" : "\(step)") { setBPM(song.bpm + step) }
                                .buttonStyle(.bordered)
                        }
                    }
                }

                Section("คีย์") {
                    TextField("เช่น C, Am", text: Binding(
                        get: { song.key },
                        set: { key in save { $0.key = key } }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }

                if midi.active == .nuxDualLoop {
                    nuxMemorySection
                } else {
                drumSetSection
                if !frequentBeats.isEmpty {
                    Section("ใช้บ่อย") {
                        ForEach(frequentBeats, id: \.self) { pick in
                            Button {
                                choose(folder: pick.folder, beat: pick.beat)
                            } label: {
                                HStack {
                                    Text(catalog.label(folder: pick.folder, beat: pick.beat) ?? "")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if pick.folder == song.beatFolder && pick.beat == song.beatNumber {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("จังหวะ BeatBuddy · \(catalog.project)") {
                    if let current = catalog.label(folder: song.beatFolder, beat: song.beatNumber) {
                        Label(current, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    ForEach(catalog.folders.filter { !$0.beats.isEmpty }) { folder in
                        NavigationLink {
                            beatList(folder)
                        } label: {
                            HStack {
                                Text("\(folder.number). \(folder.name)")
                                Spacer()
                                if folder.number == song.beatFolder {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                    if song.beatFolder != nil {
                        Button("ไม่ใช้กลอง", systemImage: "xmark.circle", role: .destructive) {
                            save { $0.beatFolder = nil; $0.beatNumber = nil }
                        }
                    }
                }
                }
            }
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("เสร็จ") { dismiss() }
            }
        }
    }

    private func beatList(_ folder: BeatFolder) -> some View {
        List(folder.beats, id: \.number) { beat in
            Button {
                choose(folder: folder.number, beat: beat.number)
            } label: {
                HStack {
                    Text("\(beat.number). \(beat.name)").foregroundStyle(.primary)
                    Spacer()
                    if folder.number == song.beatFolder && beat.number == song.beatNumber {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
        }
        .navigationTitle(folder.name)
    }

    /// Ask Gemini for this song's BPM, style and closest beat; nothing changes until "ใช้ค่านี้".
    private var aiSection: some View {
        Section {
            if !ai.hasKey {
                Label("ใส่ Gemini API key ที่หน้าแรก › AI ค้นหาจังหวะ ก่อน", systemImage: "key")
                    .foregroundStyle(.secondary)
            } else if aiSearching {
                HStack {
                    ProgressView()
                    Text("กำลังค้นหาข้อมูลเพลง…").foregroundStyle(.secondary)
                }
            } else {
                Button("ค้นหาจังหวะด้วย AI", systemImage: "sparkles", action: runAI)
            }
            if let aiError {
                Text(aiError).font(.caption).foregroundStyle(.red)
            }
            if let s = aiSuggestion {
                VStack(alignment: .leading, spacing: 4) {
                    Text([s.style, s.timeSignature, s.bpm.map { "\($0) BPM" }, s.key.isEmpty ? nil : "คีย์ \(s.key)"]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.headline)
                    if let beat = catalog.label(folder: s.folder, beat: s.beat) {
                        Label(beat, systemImage: "music.note")
                    }
                    if let kit = s.drumSet, let name = catalog.drumSetName(kit) {
                        Label("กลอง \(name)", systemImage: "circle.grid.2x2")
                    }
                    if !s.artist.isEmpty { Text("ศิลปิน: \(s.artist)").font(.subheadline) }
                    if !s.note.isEmpty {
                        Text(s.note).font(.caption).foregroundStyle(.secondary)
                    }
                    if !s.confidence.isEmpty {
                        Text("ความมั่นใจ: \(s.confidence)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button("ใช้ค่านี้", systemImage: "checkmark.circle.fill") {
                    var updated = currentSong
                    AIBeatFinder.apply(s, to: &updated)
                    store.upsert(updated)
                    midi.load(updated)
                    aiSuggestion = nil
                }
                .font(.headline)
            }
        } header: {
            Text("AI ค้นหาจังหวะ · Gemini")
        } footer: {
            if let style = currentSong.style, aiSuggestion == nil {
                Text("สไตล์: \(style)")
            }
        }
    }

    private func runAI() {
        aiSearching = true
        aiError = nil
        aiSuggestion = nil
        Task {
            do { aiSuggestion = try await ai.suggest(for: currentSong) }
            catch { aiError = error.localizedDescription }
            aiSearching = false
        }
    }

    /// BeatBuddy kit sound for this song; sent right away and every time the song opens.
    private var drumSetSection: some View {
        Section {
            ForEach(catalog.drumSets ?? []) { kit in
                Button {
                    save { $0.drumSet = kit.number }
                    midi.selectDrumSet(kit.number)
                } label: {
                    HStack {
                        Text("\(kit.number). \(kit.name)").foregroundStyle(.primary)
                        Spacer()
                        if kit.number == song.drumSet {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
            if song.drumSet != nil {
                Button("ไม่เปลี่ยน (ใช้เสียงกลองที่ตั้งไว้ในเครื่อง)", systemImage: "xmark.circle", role: .destructive) {
                    save { $0.drumSet = nil }
                }
            }
        } header: {
            Text("Drum Set · เสียงกลอง")
        } footer: {
            Text("เลือกแล้ว BeatBuddy เปลี่ยนเสียงกลองทันที และจะส่งให้ทุกครั้งที่เปิดเพลงนี้")
        }
    }

    /// NUX Dual Loop Stereo: one phrase memory (01–99) per song.
    private var nuxMemorySection: some View {
        Section {
            HStack {
                Text(song.rhythmLabel(for: .nuxDualLoop) ?? "ยังไม่เลือก")
                    .font(.title2.monospacedDigit().bold())
                Spacer()
                ForEach([-10, -1, 1, 10], id: \.self) { step in
                    Button(step > 0 ? "+\(step)" : "\(step)") {
                        let memory = min(max((song.nuxMemory ?? 0) + step, 1), 99)
                        save { $0.nuxMemory = memory }
                        midi.selectNuxMemory(memory)
                    }
                    .buttonStyle(.bordered)
                }
            }
            if song.nuxMemory != nil {
                Button("ไม่ใช้ NUX", systemImage: "xmark.circle", role: .destructive) {
                    save { $0.nuxMemory = nil }
                }
            }
        } header: {
            Text("NUX Dual Loop · Memory")
        } footer: {
            Text("เลือก phrase memory 01–99 ที่บันทึกจังหวะ/loop ของเพลงนี้ไว้ในเครื่อง NUX")
        }
    }

    struct BeatPick: Hashable {
        var folder: Int
        var beat: Int
    }

    /// Beats already given to other songs, most used first (max 8).
    private var frequentBeats: [BeatPick] {
        var counts: [BeatPick: Int] = [:]
        for s in store.songs {
            if let f = s.beatFolder, let b = s.beatNumber { counts[BeatPick(folder: f, beat: b), default: 0] += 1 }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.folder < $1.key.folder }
            .prefix(8).map(\.key)
    }

    private func choose(folder: Int, beat: Int) {
        save { $0.beatFolder = folder; $0.beatNumber = beat }
        midi.load(currentSong)
        dismiss()
    }

    /// The saved copy, so edits made in this popover stack up.
    private var currentSong: Song {
        store.songs.first { $0.id == song.id } ?? song
    }

    private func save(_ change: (inout Song) -> Void) {
        var updated = currentSong
        change(&updated)
        updated.estimated = nil  // the user has now checked this song
        store.upsert(updated)
    }

    private func setBPM(_ bpm: Int) {
        let clamped = min(max(bpm, 40), 300)
        save { $0.bpm = clamped }
        midi.setTempo(clamped)
    }
}
