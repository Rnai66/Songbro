import SwiftUI

/// Every MIDI function of the NUX Dual Loop Stereo (NML-3DLS), from the
/// "MIDI Control" tables in its owner's manual — on its own screen, separate
/// from BeatBuddy. Commands always go to the NUX's MIDI output.
struct NUXControlView: View {
    @Environment(StageMIDI.self) private var midi
    @Environment(\.dismiss) private var dismiss

    @AppStorage("nux.tempo") private var tempo = 100.0
    @AppStorage("nux.track1Level") private var track1Level = 100.0
    @AppStorage("nux.track2Level") private var track2Level = 100.0
    @AppStorage("nux.drumLevel") private var drumLevel = 100.0
    @AppStorage("nux.octaveLevel") private var octaveLevel = 50.0
    @AppStorage("nux.boostLevel") private var boostLevel = 50.0
    @AppStorage("nux.reverbLevel") private var reverbLevel = 30.0
    @AppStorage("nux.headphones") private var headphones = 100.0
    @AppStorage("nux.master") private var master = 100.0
    @AppStorage("nux.brightness") private var brightness = 8.0

    @AppStorage("nux.ctrlAction.v2") private var ctrlAction = CtrlAction.stop.rawValue
    @AppStorage("nux.showGlobal") private var showGlobal = false

    @State private var memoryInput = 1
    @State private var clearTrack: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    status
                    memoryCard
                    trackCard(1, level: $track1Level, cc: NuxCommands.track1Level)
                    trackCard(2, level: $track2Level, cc: NuxCommands.track2Level)
                    drumCard
                    effectsCard
                    settingsCard
                    logCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("NUX Dual Loop Stereo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("เสร็จ") { dismiss() }
            }
            .confirmationDialog("ลบการอัดทั้งหมดใน Track \(clearTrack ?? 0)?",
                                isPresented: Binding(get: { clearTrack != nil }, set: { if !$0 { clearTrack = nil } }),
                                titleVisibility: .visible) {
                Button("ลบ Track \(clearTrack ?? 0)", role: .destructive) {
                    if let t = clearTrack { midi.nuxTrack(t, .clear) }
                    clearTrack = nil
                }
            } message: {
                Text("ลบเสียงที่อัดไว้ใน track นี้บนเครื่อง NUX ย้อนกลับไม่ได้")
            }
        }
    }

    // MARK: - Sections

    private var status: some View {
        HStack {
            Image(systemName: "circle.fill")
                .foregroundStyle(midi.isConnected(.nuxDualLoop) ? .green : .secondary)
            Text(midi.isConnected(.nuxDualLoop) ? "ต่อ NUX อยู่" : "ยังไม่ได้ต่อ NUX — ตั้งค่าที่หน้าแรก (เลือก NUX)")
                .font(.subheadline)
            Spacer()
            Text("Channel \(midi.connection(for: .nuxDualLoop).channel)")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var memoryCard: some View {
        card("Memory", icon: "square.stack.3d.up") {
            HStack(spacing: 16) {
                Text(midi.nuxCurrentMemory.map { String(format: "%02d", $0) } ?? "--")
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.red)
                    .frame(minWidth: 90)
                VStack(spacing: 8) {
                    HStack {
                        Button { midi.nuxStepMemory(-1) } label: { Label("−1", systemImage: "chevron.left") }
                        Button { midi.nuxStepMemory(1) } label: { Label("+1", systemImage: "chevron.right") }
                    }
                    HStack {
                        Stepper("โหลด \(String(format: "%02d", memoryInput))", value: $memoryInput, in: 1...99)
                            .fixedSize()
                        Button("โหลด") { midi.nuxLoadMemory(memoryInput) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
                ctrlButton
            }
            Picker("โหมด Loop", selection: Binding(
                get: { 0 }, set: { midi.nux(NuxCommands.loopMode, $0, $0 == 1 ? "SYNC mode" : "SPLIT mode") })) {
                Text("เลือกโหมด").tag(0)
                Text("SYNC").tag(1)
                Text("SPLIT").tag(2)
            }
            .pickerStyle(.segmented)
        }
    }

    /// The NUX's CTRL footswitch has no MIDI command of its own (it does whatever
    /// is set in the pedal's CTRL SETTING), so the app's CTRL button sends the
    /// function chosen here — pick the same one as on the pedal.
    private var ctrlButton: some View {
        let action = CtrlAction(rawValue: ctrlAction) ?? .stop
        return VStack(spacing: 6) {
            Button { action.send(midi) } label: {
                Label(action == .stop ? "CTRL · Stop" : "CTRL",
                      systemImage: action == .stop ? "stop.fill" : "circle.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            Menu {
                Picker("ปุ่ม CTRL ทำอะไร", selection: $ctrlAction) {
                    ForEach(CtrlAction.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } label: {
                Text((action == .stop ? "Stop" : action.title) + " ▾").font(.caption).lineLimit(1)
            }
        }
    }

    private func trackCard(_ track: Int, level: Binding<Double>, cc: UInt8) -> some View {
        card("Track \(track)", icon: "waveform") {
            // Full-width card; the three stage buttons are big footswitch-sized pads.
            HStack(spacing: 12) {
                bigTrackButton(track, .playStop, color: .green)
                bigTrackButton(track, .record, color: .red)
                bigTrackButton(track, .dub, color: .orange)
            }
            HStack(spacing: 8) {
                ForEach([NuxCommands.TrackAction.undo, .redo, .clear]) { action in
                    Button(role: action == .clear ? .destructive : nil) {
                        if action == .clear { clearTrack = track } else { midi.nuxTrack(track, action) }
                    } label: {
                        Label(action.title, systemImage: action.icon)
                            .lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            levelSlider("Level", value: level, range: 0...127) { midi.nux(cc, $0, "Track \(track) level \($0)") }
        }
    }

    private func bigTrackButton(_ track: Int, _ action: NuxCommands.TrackAction, color: Color) -> some View {
        Button { midi.nuxTrack(track, action) } label: {
            VStack(spacing: 8) {
                Image(systemName: action.icon).font(.system(size: 38, weight: .semibold))
                Text(action.title).font(.title2.bold())
            }
            .frame(maxWidth: .infinity, minHeight: 110)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
    }

    private var drumCard: some View {
        card("Drum", icon: "metronome") {
            HStack {
                Button { midi.nuxDrumToggle() } label: {
                    Label("กลอง เปิด/ปิด", systemImage: "playpause.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Button { midi.nux(NuxCommands.tapTempo, 1, "Tap tempo") } label: {
                    Label("TAP", systemImage: "hand.tap").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            HStack {
                Text("Tempo").frame(width: 70, alignment: .leading)
                Button("−") { setTempo(tempo - 1) }
                Slider(value: $tempo, in: 30...250, step: 1) { editing in
                    if !editing { midi.nuxTempo(Int(tempo)) }
                }
                Button("+") { setTempo(tempo + 1) }
                Text("\(Int(tempo))").monospacedDigit().frame(width: 44)
            }
            .buttonStyle(.bordered)
            Picker("จังหวะ", selection: Binding(
                get: { 0 }, set: { midi.nux(NuxCommands.timeSignature, $0, $0 == 1 ? "Beat 4/4" : "Beat 3/4") })) {
                Text("Beat").tag(0)
                Text("4/4").tag(1)
                Text("3/4").tag(2)
            }
            .pickerStyle(.segmented)
            levelSlider("Drum level", value: $drumLevel, range: 0...127) { midi.nux(NuxCommands.drumLevel, $0, "Drum level \($0)") }
            Text("เลือกสไตล์กลองให้แต่ละเพลงได้ผ่าน Memory (บันทึกไว้ในเครื่อง NUX)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var effectsCard: some View {
        card("Effects", icon: "slider.horizontal.3") {
            effectRow("Octave", toggle: NuxCommands.octaveOnOff, level: $octaveLevel, levelCC: NuxCommands.octaveLevel)
            effectRow("Boost", toggle: NuxCommands.boostOnOff, level: $boostLevel, levelCC: NuxCommands.boostLevel)
            effectRow("Reverb (กลอง)", toggle: NuxCommands.reverbOnOff, level: $reverbLevel, levelCC: NuxCommands.reverbLevel)
            HStack {
                Text("Cabinet sim").frame(width: 120, alignment: .leading)
                Button("เปิด/ปิด") { midi.nux(NuxCommands.cabOnOff, 1, "CAB on/off") }
                    .buttonStyle(.bordered)
                Spacer()
            }
        }
    }

    private var settingsCard: some View {
        DisclosureGroup(isExpanded: $showGlobal) {
            VStack(alignment: .leading, spacing: 12) {
            modeMenu("REC mode", [("Instant", .recInstant), ("Detecting", .recDetecting), ("Pre-beat", .recPreBeat)])
            modeMenu("DUB mode", [("Rec-Play-Dub", .dubRecPlayDub), ("Rec-Dub-Play", .dubRecDubPlay)])
            modeMenu("STOP mode", [("Normal", .stopNormal), ("One shot", .stopOneShot),
                                   ("Loop end", .stopLoopEnd), ("Fade out", .stopFadeOut)])
            modeMenu("Audio path", [("Mic/Inst (mono)", .pathMicInstMono), ("Stereo in/out", .pathStereo),
                                    ("Split in/out", .pathSplit)])
            levelSlider("Master", value: $master, range: 0...127) { midi.nux(NuxCommands.master, $0, "Master \($0)") }
            levelSlider("Headphones", value: $headphones, range: 0...127) { midi.nux(NuxCommands.headphones, $0, "Headphones \($0)") }
            levelSlider("ความสว่างจอ", value: $brightness, range: 0...10) { midi.nux(NuxCommands.brightness, $0, "Brightness \($0)") }
            }
            .padding(.top, 12)
        } label: {
            Label("Global Setting", systemImage: "gearshape").font(.headline)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var logCard: some View {
        card("คำสั่งที่ส่งล่าสุด", icon: "list.bullet") {
            let lines = midi.log.filter { $0.contains("[NUX]") }.prefix(8)
            if lines.isEmpty {
                Text("ยังไม่มี").foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Building blocks

    private func card<Content: View>(_ title: String, icon: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    /// Sends when the finger lifts, so dragging doesn't flood the MIDI link.
    private func levelSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                             send: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(title).frame(width: 110, alignment: .leading)
            Slider(value: value, in: range, step: 1) { editing in
                if !editing { send(Int(value.wrappedValue)) }
            }
            Text("\(Int(value.wrappedValue))").monospacedDigit().frame(width: 40)
        }
    }

    private func effectRow(_ title: String, toggle: UInt8, level: Binding<Double>, levelCC: UInt8) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).frame(width: 120, alignment: .leading)
                Button("เปิด/ปิด") { midi.nux(toggle, 1, "\(title) on/off") }
                    .buttonStyle(.bordered)
                Spacer()
            }
            levelSlider("ระดับ", value: level, range: 0...100) { midi.nux(levelCC, $0, "\(title) level \($0)") }
        }
    }

    private func modeMenu(_ title: String, _ options: [(String, NuxCommands.GlobalMode)]) -> some View {
        HStack {
            Text(title).frame(width: 110, alignment: .leading)
            ForEach(options, id: \.0) { name, mode in
                Button(name) { midi.nuxGlobal(mode, "\(title): \(name)") }
                    .buttonStyle(.bordered)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func setTempo(_ value: Double) {
        tempo = min(max(value, 30), 250)
        midi.nuxTempo(Int(tempo))
    }
}

/// What the app's CTRL button does. Default is Stop, like the right-hand CTRL
/// footswitch on the user's NUX.
enum CtrlAction: String, CaseIterable, Identifiable {
    case stop, tapTempo, drumOnOff, track1PlayStop, track2PlayStop, track1Undo, track2Undo, memoryUp, memoryDown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stop: "Stop (เหมือนสวิตช์ CTRL บนเครื่อง)"
        case .tapTempo: "Tap tempo"
        case .drumOnOff: "กลอง เปิด/ปิด"
        case .track1PlayStop: "Track 1 Play/Stop"
        case .track2PlayStop: "Track 2 Play/Stop"
        case .track1Undo: "Track 1 Undo"
        case .track2Undo: "Track 2 Undo"
        case .memoryUp: "Memory +1"
        case .memoryDown: "Memory −1"
        }
    }

    func send(_ midi: StageMIDI) {
        switch self {
        case .stop: midi.nuxStop()
        case .tapTempo: midi.nux(NuxCommands.tapTempo, 1, "CTRL: Tap tempo")
        case .drumOnOff: midi.nuxDrumToggle()
        case .track1PlayStop: midi.nuxTrack(1, .playStop)
        case .track2PlayStop: midi.nuxTrack(2, .playStop)
        case .track1Undo: midi.nuxTrack(1, .undo)
        case .track2Undo: midi.nuxTrack(2, .undo)
        case .memoryUp: midi.nuxStepMemory(1)
        case .memoryDown: midi.nuxStepMemory(-1)
        }
    }
}
