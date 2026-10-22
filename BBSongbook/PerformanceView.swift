import SwiftUI

/// Stage view: lyrics, rhythm-machine controls, beat-synced auto scroll.
struct PerformanceView: View {
    let song: Song
    var onEdit: () -> Void

    @Environment(StageMIDI.self) private var midi
    @AppStorage("autoSendOnOpen") private var autoSend = true
    @AppStorage("fontSize") private var fontSize = 28.0
    /// How many beats each lyric line lasts (8 = two bars of 4/4).
    @AppStorage("beatsPerLine") private var beatsPerLine = 8

    @State private var transpose = 0
    @State private var playing = false
    @State private var autoScroll = false
    @State private var currentLine: Int? = 0
    /// Moves the lyric sheet image (songs from the song folder).
    @State private var sheetCommand = ScrollCommand()
    @State private var showQuickSettings = false
    @FocusState private var focused: Bool

    private var lines: [ChordPro.Line] {
        ChordPro.parse(ChordPro.transpose(song.lyrics, by: transpose))
    }

    private var lineInterval: TimeInterval {
        60.0 / Double(max(song.bpm, 1)) * Double(beatsPerLine)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let path = song.filePath {
                SheetImageView(path: path, command: sheetCommand)
            } else {
                lyrics
            }
            Divider()
            controls
        }
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("แก้ไข", systemImage: "pencil", action: onEdit)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        // Bluetooth page-turner pedals usually send arrow / page keys.
        .onKeyPress(keys: [.downArrow, .rightArrow, .pageDown]) { _ in step(1); return .handled }
        .onKeyPress(keys: [.upArrow, .leftArrow, .pageUp]) { _ in step(-1); return .handled }
        .onKeyPress(.space) { togglePlay(); return .handled }
        .onAppear {
            focused = true
            if autoSend { midi.load(song) }
        }
        .onDisappear { autoScroll = false }
        .task(id: autoScroll ? lineInterval : 0) {
            guard autoScroll else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(lineInterval))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.6)) { step(1) }
            }
        }
    }

    /// Tap any chip to change key / BPM / rhythm right here (saved and sent to the active device).
    private var header: some View {
        HStack(spacing: 10) {
            Button { showQuickSettings = true } label: {
                HStack(spacing: 10) {
                    infoChip("คีย์", song.key.isEmpty ? "-" : ChordPro.transposeChord(song.key, by: transpose))
                    infoChip("BPM", "\(song.bpm)")
                    infoChip("จังหวะ BeatBuddy ▾",
                             BeatCatalog.bundled.label(folder: song.beatFolder, beat: song.beatNumber) ?? "แตะเพื่อเลือก")
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showQuickSettings, arrowEdge: .top) {
                QuickBeatSettings(song: song)
                    .frame(minWidth: 400, idealWidth: 440, minHeight: 720)
            }
            Spacer(minLength: 0)
            if !song.artist.isEmpty {
                Text(song.artist).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func infoChip(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var lyrics: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: fontSize * 0.5) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    lineView(line)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(autoScroll && index == currentLine ? Color.accentColor.opacity(0.12) : .clear))
                        .id(index)
                        .onTapGesture { currentLine = index }
                }
            }
            .scrollTargetLayout()
            .padding(24)
            .padding(.bottom, 300)
        }
        .scrollPosition(id: $currentLine, anchor: .top)
    }

    @ViewBuilder
    private func lineView(_ line: ChordPro.Line) -> some View {
        switch line {
        case .blank:
            Spacer().frame(height: fontSize * 0.4)
        case .section(let name):
            Text(name)
                .font(.system(size: fontSize * 0.7, weight: .bold))
                .foregroundStyle(.orange)
                .padding(.top, fontSize * 0.3)
        case .lyric(let segments):
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(seg.chord.isEmpty ? " " : seg.chord + " ")
                            .font(.system(size: fontSize * 0.8, weight: .bold))
                            .foregroundStyle(.blue)
                        Text(seg.text.isEmpty ? " " : seg.text)
                            .font(.system(size: fontSize))
                    }
                }
            }
        }
    }

    /// Two rows so it fits the narrow detail column in portrait.
    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: togglePlay) {
                    Label(playing ? "หยุด" : "เริ่ม", systemImage: playing ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(playing ? .red : .green)

                Button { midi.fill() } label: {
                    Label("Fill", systemImage: "music.quarternote.3").frame(maxWidth: .infinity)
                }
                .disabled(!midi.supportsFillAndParts)
                Button { midi.nextPart() } label: {
                    Label("ถัดไป", systemImage: "forward.end.fill").frame(maxWidth: .infinity)
                }
                .disabled(!midi.supportsFillAndParts)
                Button { midi.load(song) } label: {
                    Label("ส่ง", systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .lineLimit(1)

            HStack(spacing: 12) {
                Toggle(isOn: $autoScroll) { Label("เลื่อนตามจังหวะ", systemImage: "arrow.down.circle") }
                    .toggleStyle(.button)
                Spacer(minLength: 0)
                Text(song.filePath == nil ? "\(beatsPerLine) จังหวะ/บรรทัด" : "เลื่อนทุก \(beatsPerLine) จังหวะ")
                    .monospacedDigit()
                Stepper("", value: $beatsPerLine, in: 2...32, step: 2).labelsHidden()
                Menu {
                    if song.filePath == nil {
                        Stepper("ตัวอักษร \(Int(fontSize))", value: $fontSize, in: 16...60, step: 2)
                        Stepper("เปลี่ยนคีย์ \(transpose > 0 ? "+" : "")\(transpose)", value: $transpose, in: -11...11)
                    }
                    Toggle("ส่งจังหวะอัตโนมัติเมื่อเปิดเพลง", isOn: $autoSend)
                } label: { Image(systemName: "textformat.size").font(.title3) }
            }
            .lineLimit(1)
        }
        .padding()
        .background(.bar)
    }

    private func togglePlay() {
        if playing {
            midi.stop()
            autoScroll = false
        } else {
            midi.start()
            currentLine = 0
            sheetCommand = ScrollCommand(toTop: true)
            autoScroll = true
        }
        playing.toggle()
    }

    private func step(_ delta: Int) {
        if song.filePath != nil {
            sheetCommand = ScrollCommand(delta: delta)
            return
        }
        let next = (currentLine ?? 0) + delta
        currentLine = min(max(next, 0), max(lines.count - 1, 0))
    }
}
