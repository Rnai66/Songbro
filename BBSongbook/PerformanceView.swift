import SwiftUI

/// Stage view: lyrics, rhythm-machine controls, beat-synced auto scroll.
struct PerformanceView: View {
    let song: Song
    /// The set on screen (folder songs in file-name order), to pick the next song from.
    var setSongs: [Song] = []
    var onEdit: () -> Void
    /// Opens another song (next/previous in the set).
    var onOpen: (Song) -> Void = { _ in }

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
    @State private var showSetPicker = false
    /// Song picked with the pedal but not opened yet — a second press opens it,
    /// so one stray tap never changes song mid-performance.
    @State private var cued: Song?
    /// Transition button / Return key is being held down.
    @State private var holdingTransition = false
    @FocusState private var focused: Bool

    private var setIndex: Int? { setSongs.firstIndex { $0.id == song.id } }

    private var previous: Song? {
        guard let i = setIndex, i > 0 else { return nil }
        return setSongs[i - 1]
    }

    private var next: Song? {
        guard let i = setIndex, i + 1 < setSongs.count else { return nil }
        return setSongs[i + 1]
    }

    private var lines: [ChordPro.Line] {
        ChordPro.parse(ChordPro.transpose(song.lyrics, by: transpose))
    }

    private var lineInterval: TimeInterval {
        60.0 / Double(max(song.bpm, 1)) * Double(beatsPerLine)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let cued {
                cueBanner(cued)
            }
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
        // Bluetooth page-turner pedals send arrow / page keys:
        // down/up and page keys scroll the sheet; right/left pick a song in the
        // set in two steps (right = cue next / open the cued song, left = cue
        // previous / cancel the cue).
        .onKeyPress(keys: [.downArrow, .pageDown]) { _ in step(1); return .handled }
        .onKeyPress(keys: [.upArrow, .pageUp]) { _ in step(-1); return .handled }
        .onKeyPress(.rightArrow) {
            if let cued { go(to: cued) } else { cued = next }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if cued != nil { cued = nil } else { cued = previous }
            return .handled
        }
        .onKeyPress(.space) { togglePlay(); return .handled }
        // Return/Enter works like the BeatBuddy pedal: hold = transition fill
        // loops in the same beat, release = go to the next part.
        .onKeyPress(.return, phases: [.down, .up]) { press in
            press.phase == .down ? holdTransition() : releaseTransition()
            return .handled
        }
        .onAppear {
            focused = true
            if autoSend { midi.load(song) }
        }
        .onDisappear {
            autoScroll = false
            releaseTransition()
        }
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
        // One row when it fits (landscape); otherwise the next-song button
        // drops to a second row so the chips keep their names readable.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                chipsButton
                Spacer(minLength: 0)
                setNavigation
            }
            VStack(alignment: .leading, spacing: 8) {
                chipsButton
                HStack {
                    Spacer(minLength: 0)
                    setNavigation
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var chipsButton: some View {
        Button { showQuickSettings = true } label: {
            HStack(spacing: 10) {
                infoChip("คีย์", song.key.isEmpty ? "-" : ChordPro.transposeChord(song.key, by: transpose))
                infoChip("BPM", "\(song.estimated == true ? "≈" : "")\(song.bpm)")
                infoChip(midi.active == .nuxDualLoop ? "NUX ▾" : "จังหวะ ▾",
                         song.rhythmLabel(for: midi.active) ?? "แตะเพื่อเลือก")
                if midi.active == .beatBuddy {
                    infoChip("กลอง ▾", BeatCatalog.bundled.drumSetName(song.drumSet) ?? "ตามเครื่อง")
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showQuickSettings, arrowEdge: .top) {
            QuickBeatSettings(song: song)
                .frame(minWidth: 400, idealWidth: 440, minHeight: 720)
        }
    }

    /// Shows what comes next in the set; tapping opens the set list to choose
    /// any song — nothing changes until a song is picked.
    private var setNavigation: some View {
        Button { showSetPicker = true } label: {
            VStack(alignment: .trailing, spacing: 2) {
                Text("ถัดไป ▾").font(.caption).foregroundStyle(.secondary)
                Text(next?.title ?? "จบ set").font(.headline).lineLimit(1)
            }
            .frame(maxWidth: 220, alignment: .trailing)
        }
        .buttonStyle(.bordered)
        .disabled(setSongs.count < 2)
        .popover(isPresented: $showSetPicker, arrowEdge: .top) {
            setPicker
                .frame(minWidth: 360, idealWidth: 400, minHeight: 480)
        }
    }

    /// The whole set; the current song is marked and the next one is first in line.
    private var setPicker: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(Array(setSongs.enumerated()), id: \.element.id) { index, item in
                    Button {
                        showSetPicker = false
                        go(to: item)
                    } label: {
                        HStack {
                            Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                            Text(item.title).foregroundStyle(.primary)
                            Spacer()
                            if item.id == song.id {
                                Text("กำลังเล่น").font(.caption.bold()).foregroundStyle(.green)
                            } else if item.id == next?.id {
                                Text("ถัดไป").font(.caption.bold()).foregroundStyle(.tint)
                            }
                        }
                    }
                    .disabled(item.id == song.id)
                    .id(item.id)
                }
                .onAppear { proxy.scrollTo(song.id, anchor: .top) }
            }
            .navigationTitle("เลือกเพลงถัดไป")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("ปิด") { showSetPicker = false }
            }
        }
    }

    /// Pedal picked a song: show it and wait for a second press.
    private func cueBanner(_ cued: Song) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "forward.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("เตรียมเปิด: \(cued.title)").font(.headline).lineLimit(1)
                Text("เหยียบขวาอีกครั้งเพื่อเปิด · เหยียบซ้ายเพื่อยกเลิก")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("ยกเลิก") { self.cued = nil }
                .buttonStyle(.bordered)
            Button("เปิด") { go(to: cued) }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
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
                HoldButton(pressed: holdingTransition,
                           onPress: holdTransition,
                           onRelease: releaseTransition) {
                    Label(holdingTransition ? "ปล่อย = ท่อนถัดไป" : "Transition",
                          systemImage: "forward.end.fill")
                }
                .disabled(!midi.supportsFillAndParts)
                Button { midi.togglePause() } label: {
                    Label(midi.paused ? "ต่อ" : "Pause",
                          systemImage: midi.paused ? "playpause.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(midi.paused ? .orange : nil)
                .disabled(!midi.supportsFillAndParts || !playing)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .lineLimit(1)

            HStack(spacing: 12) {
                Toggle(isOn: $autoScroll) { Label("เลื่อนตามจังหวะ", systemImage: "arrow.down.circle") }
                    .toggleStyle(.button)
                Button("ส่งจังหวะ", systemImage: "paperplane") { midi.load(song) }
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

    /// Pedal/button down: start the transition and keep it looping.
    private func holdTransition() {
        guard !holdingTransition, midi.supportsFillAndParts else { return }
        holdingTransition = true
        midi.beginTransition()
    }

    /// Pedal/button up: BeatBuddy moves on to the next part.
    private func releaseTransition() {
        guard holdingTransition else { return }
        holdingTransition = false
        midi.endTransition()
    }

    /// Opens another song in the set. The current song is over, so the drums
    /// stop first; the new song sends its own beat/memory and BPM when it opens.
    @discardableResult
    private func go(to song: Song?) -> Bool {
        guard let song else { return false }
        cued = nil
        releaseTransition()
        if playing {
            midi.stop()
            playing = false
        }
        autoScroll = false
        onOpen(song)
        return true
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

/// A button that reports press and release separately, like a footswitch,
/// styled to match the bordered buttons beside it.
private struct HoldButton<Label: View>: View {
    var pressed: Bool
    var onPress: () -> Void
    var onRelease: () -> Void
    @ViewBuilder var label: Label

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .lineLimit(1)
            .font(.body.weight(.medium))
            .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(pressed ? Color.orange.opacity(0.35) : Color.secondary.opacity(0.15),
                        in: Capsule())
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if isEnabled && !pressed { onPress() } }
                    .onEnded { _ in onRelease() }
            )
            .accessibilityAddTraits(.isButton)
    }
}
