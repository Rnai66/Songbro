import CoreMIDI
import Foundation
import Observation

/// The rhythm machine SongBro is driving right now.
enum StageDevice: String, CaseIterable, Identifiable, Codable {
    case beatBuddy
    case nuxDualLoop

    var id: String { rawValue }

    var name: String {
        switch self {
        case .beatBuddy: "BeatBuddy"
        case .nuxDualLoop: "NUX Dual Loop Stereo (NML-3DLS)"
        }
    }

    var shortName: String {
        switch self {
        case .beatBuddy: "BeatBuddy"
        case .nuxDualLoop: "NUX"
        }
    }

    var icon: String {
        switch self {
        case .beatBuddy: "metronome"
        case .nuxDualLoop: "repeat.circle"
        }
    }
}

/// Which MIDI output and channel a device listens on.
struct DeviceConnection: Codable, Equatable {
    /// nil = send to every connected MIDI output.
    var destinationID: MIDIUniqueID?
    /// MIDI channel 1–16, as set on the device.
    var channel = 1
}

/// NUX NML-3DLS (Dual Loop Stereo) MIDI map, from the "MIDI Control" tables
/// in the NUX owner's manual. The NUX has no drum fill or part-change command.
enum NuxCommands {
    static let memoryStep: UInt8 = 10    // 1 = memory +1, 2 = memory −1
    static let loadMemory: UInt8 = 11    // value 01–99 = memory number
    static let loopMode: UInt8 = 12      // 1 = SYNC, 2 = SPLIT
    static let track1: UInt8 = 20        // TrackAction raw value
    static let track1Level: UInt8 = 23   // 0–127
    static let track2: UInt8 = 24
    static let track2Level: UInt8 = 27
    static let drumOnOff: UInt8 = 30     // value 01, toggles the drum
    static let drumLevel: UInt8 = 33     // 0–127
    static let tapTempo: UInt8 = 34      // 1 per tap
    static let timeSignature: UInt8 = 35 // 1 = 4/4, 2 = 3/4
    static let tempoLow: UInt8 = 37      // value 30–100 = 30–100 BPM
    static let tempoMid: UInt8 = 38      // value 01–100 = 101–200 BPM
    static let tempoHigh: UInt8 = 39     // value 01–50 = 201–250 BPM
    static let tempoUp: UInt8 = 40       // value = steps
    static let tempoDown: UInt8 = 41
    static let octaveOnOff: UInt8 = 50, octaveLevel: UInt8 = 51   // level 0–100
    static let boostOnOff: UInt8 = 52, boostLevel: UInt8 = 53
    static let cabOnOff: UInt8 = 54
    static let reverbOnOff: UInt8 = 55, reverbLevel: UInt8 = 56   // reverb is for the drum only
    static let brightness: UInt8 = 62    // 0–10
    static let globalMode: UInt8 = 63    // see GlobalMode
    static let headphones: UInt8 = 66    // 0–127
    static let master: UInt8 = 69        // 0–127
    static let tempoRange = 30...250

    /// CC20 / CC24 values for each looper track.
    enum TrackAction: Int, CaseIterable, Identifiable {
        case playStop = 1, record, dub, undo, redo, clear
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .playStop: "Play"
            case .record: "Rec"
            case .dub: "Dub"
            case .undo: "Undo"
            case .redo: "Redo"
            case .clear: "Clear"
            }
        }
        var icon: String {
            switch self {
            case .playStop: "playpause.fill"
            case .record: "record.circle"
            case .dub: "plus.circle"
            case .undo: "arrow.uturn.backward"
            case .redo: "arrow.uturn.forward"
            case .clear: "trash"
            }
        }
    }

    /// CC63 values from the "Global Setting" table.
    enum GlobalMode: Int {
        case recInstant = 1, recDetecting, recPreBeat
        case dubRecPlayDub, dubRecDubPlay
        case stopNormal, stopOneShot, stopLoopEnd, stopFadeOut
        case pathMicInstMono, pathStereo, pathSplit
    }
}

/// Sends rhythm-machine commands over CoreMIDI (USB MIDI interface or Bluetooth MIDI)
/// to the active device — BeatBuddy or NUX Dual Loop Stereo.
///
/// BeatBuddy folder/beat select and tempo follow its MIDI spec:
/// Bank Select (CC0 MSB + CC32 LSB) = folder, Program Change = beat,
/// CC106/CC107 = tempo MSB/LSB. Everything is 0-based on the wire, so
/// BBManager's "28. Thai Style" goes out as folder 27.
/// The remaining BeatBuddy CC numbers live in `BeatBuddyCommands` — check them
/// against the MIDI manual for your firmware.
@Observable
final class StageMIDI {
    enum BeatBuddyCommands {
        static let bankMSB: UInt8 = 0
        static let bankLSB: UInt8 = 32
        static let tempoMSB: UInt8 = 106
        static let tempoLSB: UInt8 = 107
        // Starts a transition that loops until the value goes back to 0; the value
        // picks the part to go to on release (127 = next part). CC102 is only
        // what BeatBuddy sends out after a transition, it doesn't act on it.
        static let transition: UInt8 = 113
        static let drumFill: UInt8 = 112
        static let drumSet: UInt8 = 116       // value = drum set (see drumSetZeroBased)
        static let pause: UInt8 = 111         // 1 = pause, 0 = continue (toggle values are unreliable)
    }

    struct Destination: Identifiable, Hashable {
        let id: MIDIUniqueID
        let name: String
    }

    private(set) var destinations: [Destination] = []
    private(set) var log: [String] = []

    var active: StageDevice {
        didSet { save() }
    }
    var connections: [StageDevice: DeviceConnection] {
        didSet { save() }
    }

    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()

    private static let settingsKey = "stageMIDISettings"

    /// Forum reports differ on whether CC116 value 0 or 1 picks the first drum set,
    /// so it's a setting (off = value 1 is the first set).
    var drumSetZeroBased = false {
        didSet { save() }
    }

    private struct Saved: Codable {
        var active: StageDevice
        var connections: [StageDevice: DeviceConnection]
        var drumSetZeroBased: Bool?
    }

    init() {
        let saved = UserDefaults.standard.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        active = saved?.active ?? .beatBuddy
        connections = saved?.connections ?? [:]
        drumSetZeroBased = saved?.drumSetZeroBased ?? false

        MIDIClientCreateWithBlock("SongBro" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        MIDIOutputPortCreate(client, "SongBro Out" as CFString, &outPort)
        // Wi-Fi MIDI ("Network Session 1"), e.g. to test against a Mac
        // running tools/stage_emulator.swift without the real pedals.
        MIDINetworkSession.default().isEnabled = true
        MIDINetworkSession.default().connectionPolicy = .anyone
        refresh()
    }

    private func save() {
        let data = try? JSONEncoder().encode(Saved(active: active, connections: connections,
                                                          drumSetZeroBased: drumSetZeroBased))
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }

    func connection(for device: StageDevice) -> DeviceConnection {
        connections[device] ?? DeviceConnection()
    }

    func setConnection(_ connection: DeviceConnection, for device: StageDevice) {
        connections[device] = connection
    }

    func refresh() {
        destinations = (0..<MIDIGetNumberOfDestinations()).compactMap { i in
            let endpoint = MIDIGetDestination(i)
            var uid: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uid)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
            return Destination(id: uid, name: (name?.takeRetainedValue() as String?) ?? "MIDI \(i + 1)")
        }
    }

    /// True when the device's chosen output (or any output, if none chosen) is plugged in.
    func isConnected(_ device: StageDevice) -> Bool {
        guard let id = connection(for: device).destinationID else { return !destinations.isEmpty }
        return destinations.contains { $0.id == id }
    }

    var isConnected: Bool { isConnected(active) }

    // MARK: - Commands for the active device

    /// Everything a song needs before the count-in.
    func load(_ song: Song) {
        switch active {
        case .beatBuddy:
            if let folder = song.beatFolder, let beat = song.beatNumber {
                selectBeat(folder: folder, beat: beat)
            }
            // After the beat, so the song's own default kit doesn't override it.
            if let drumSet = song.drumSet { selectDrumSet(drumSet) }
        case .nuxDualLoop:
            if let memory = song.nuxMemory { selectNuxMemory(memory) }
        }
        setTempo(song.bpm)
    }

    /// BeatBuddy: select a beat using BBManager's 1-based folder and beat numbers.
    func selectBeat(folder: Int, beat: Int) {
        let f = max(folder - 1, 0)
        send(controlChange: BeatBuddyCommands.bankMSB, value: UInt8(f >> 7 & 0x7F))
        send(controlChange: BeatBuddyCommands.bankLSB, value: UInt8(f & 0x7F))
        send(programChange: UInt8(clamping: max(beat - 1, 0)))
        note("เลือกจังหวะ โฟลเดอร์ \(folder) จังหวะ \(beat)")
    }

    /// BeatBuddy: switch the drum kit sound (1-based, as in BBManager).
    func selectDrumSet(_ number: Int) {
        guard active == .beatBuddy else { return }
        let value = drumSetZeroBased ? number - 1 : number
        send(controlChange: BeatBuddyCommands.drumSet, value: UInt8(clamping: min(max(value, 0), 127)))
        note("Drum Set \(number) · \(BeatCatalog.bundled.drumSetName(number) ?? "")")
    }

    /// NUX: recall phrase memory 01–99.
    func selectNuxMemory(_ memory: Int) {
        let m = min(max(memory, 1), 99)
        send(controlChange: NuxCommands.loadMemory, value: UInt8(m))
        note(String(format: "NUX memory %02d", m))
    }

    func setTempo(_ bpm: Int) {
        switch active {
        case .beatBuddy:
            let t = min(max(bpm, 40), 300)
            send(controlChange: BeatBuddyCommands.tempoMSB, value: UInt8(t >> 7))
            send(controlChange: BeatBuddyCommands.tempoLSB, value: UInt8(t & 0x7F))
            note("ตั้ง BPM \(t)")
        case .nuxDualLoop:
            // NUX splits tempo across three CCs by range.
            let t = min(max(bpm, NuxCommands.tempoRange.lowerBound), NuxCommands.tempoRange.upperBound)
            switch t {
            case ...100: send(controlChange: NuxCommands.tempoLow, value: UInt8(t))
            case ...200: send(controlChange: NuxCommands.tempoMid, value: UInt8(t - 100))
            default: send(controlChange: NuxCommands.tempoHigh, value: UInt8(t - 200))
            }
            note("ตั้ง BPM \(t)")
        }
    }

    /// The NUX drum only has an on/off toggle, so remember what we last told it.
    private var nuxDrumRunning = false

    func start() {
        paused = false
        switch active {
        case .beatBuddy:
            send(realtime: 0xFA)
        case .nuxDualLoop:
            guard !nuxDrumRunning else { return note("NUX: กลองเล่นอยู่แล้ว") }
            send(controlChange: NuxCommands.drumOnOff, value: 1)
            nuxDrumRunning = true
        }
        note("Start")
    }

    func stop() {
        paused = false
        switch active {
        case .beatBuddy:
            send(realtime: 0xFC)
        case .nuxDualLoop:
            guard nuxDrumRunning else { return note("NUX: กลองหยุดอยู่แล้ว") }
            send(controlChange: NuxCommands.drumOnOff, value: 1)
            nuxDrumRunning = false
        }
        note("Stop")
    }

    /// NUX: flip the drum on/off without the app's bookkeeping, for when the
    /// pedal on the floor got pressed and the two disagree.
    func toggleNuxDrum() {
        send(controlChange: NuxCommands.drumOnOff, value: 1)
        nuxDrumRunning.toggle()
        note("NUX: สลับกลอง เปิด/ปิด")
    }

    /// False when the active device has no such command (NUX: no fill / part change).
    var supportsFillAndParts: Bool { active == .beatBuddy }

    func fill() {
        guard supportsFillAndParts else { return note("NUX ไม่มีคำสั่ง Fill") }
        send(controlChange: BeatBuddyCommands.drumFill, value: 127)
        note("Fill")
    }

    /// Like holding the BeatBuddy pedal down: the transition fill keeps
    /// looping in the current beat until `endTransition()`.
    func beginTransition() {
        guard supportsFillAndParts else { return note("NUX ไม่มีคำสั่งเปลี่ยนท่อน") }
        send(controlChange: BeatBuddyCommands.transition, value: 127)
        note("Transition: เริ่ม (ค้างไว้)")
    }

    /// Like releasing the pedal: BeatBuddy finishes the transition and moves
    /// to the next part. Without this it stays on "Transition".
    func endTransition() {
        guard supportsFillAndParts else { return }
        send(controlChange: BeatBuddyCommands.transition, value: 0)
        note("Transition: ปล่อย → ท่อนถัดไป")
    }

    /// A quick tap: start and release straight away.
    func nextPart() {
        beginTransition()
        endTransition()
    }

    /// BeatBuddy is paused (we track it, because its toggle value is unreliable).
    private(set) var paused = false

    /// Pause / continue the song in place, without ending it like Stop does.
    func togglePause() {
        guard supportsFillAndParts else { return note("NUX ไม่มีคำสั่ง Pause") }
        paused.toggle()
        send(controlChange: BeatBuddyCommands.pause, value: paused ? 1 : 0)
        note(paused ? "Pause" : "ต่อ (Unpause)")
    }

    // MARK: - NUX control panel (always sent to the NUX's own MIDI output)

    /// Memory the NUX was last told to load (it doesn't report back over MIDI).
    private(set) var nuxCurrentMemory: Int?

    func nux(_ cc: UInt8, _ value: Int, _ label: String) {
        send(controlChange: cc, value: UInt8(clamping: min(max(value, 0), 127)), to: .nuxDualLoop)
        note(label, device: .nuxDualLoop)
    }

    func nuxLoadMemory(_ memory: Int) {
        let m = min(max(memory, 1), 99)
        nuxCurrentMemory = m
        nux(NuxCommands.loadMemory, m, String(format: "Memory %02d", m))
    }

    func nuxStepMemory(_ delta: Int) {
        nux(NuxCommands.memoryStep, delta > 0 ? 1 : 2, delta > 0 ? "Memory +1" : "Memory −1")
        if let m = nuxCurrentMemory { nuxCurrentMemory = min(max(m + delta, 1), 99) }
    }

    func nuxTrack(_ track: Int, _ action: NuxCommands.TrackAction) {
        nux(track == 1 ? NuxCommands.track1 : NuxCommands.track2, action.rawValue, "Track \(track): \(action.title)")
    }

    func nuxTempo(_ bpm: Int) {
        let t = min(max(bpm, NuxCommands.tempoRange.lowerBound), NuxCommands.tempoRange.upperBound)
        switch t {
        case ...100: nux(NuxCommands.tempoLow, t, "Tempo \(t)")
        case ...200: nux(NuxCommands.tempoMid, t - 100, "Tempo \(t)")
        default: nux(NuxCommands.tempoHigh, t - 200, "Tempo \(t)")
        }
    }

    func nuxDrumToggle() {
        nux(NuxCommands.drumOnOff, 1, "กลอง เปิด/ปิด")
        nuxDrumRunning.toggle()
    }

    /// Like the NUX's right-hand CTRL footswitch (set to STOP): MIDI Stop, and
    /// the drum off if the app last turned it on. The manual has no "stop all"
    /// CC, so this relies on the NUX honouring MIDI Stop.
    func nuxStop() {
        send(realtime: 0xFC, to: .nuxDualLoop)
        if nuxDrumRunning {
            send(controlChange: NuxCommands.drumOnOff, value: 1, to: .nuxDualLoop)
            nuxDrumRunning = false
        }
        note("CTRL: Stop", device: .nuxDualLoop)
    }

    /// Diagnostics: which single message really stops the NUX, whatever its state.
    func nuxTestMidiStopOnly() {
        send(realtime: 0xFC, to: .nuxDualLoop)
        note("ทดสอบ: MIDI Stop อย่างเดียว", device: .nuxDualLoop)
    }

    func nuxTestDrumValueZero() {
        send(controlChange: NuxCommands.drumOnOff, value: 0, to: .nuxDualLoop)
        note("ทดสอบ: CC30 ค่า 0", device: .nuxDualLoop)
    }

    func nuxGlobal(_ mode: NuxCommands.GlobalMode, _ label: String) {
        nux(NuxCommands.globalMode, mode.rawValue, label)
    }

    // MARK: - Sending

    private func statusChannel(_ device: StageDevice) -> UInt32 {
        UInt32(min(max(connection(for: device).channel, 1), 16) - 1)
    }

    private func send(controlChange cc: UInt8, value: UInt8, to device: StageDevice? = nil) {
        let device = device ?? active
        sendUMP(0x2000_0000 | (0xB0 | statusChannel(device)) << 16 | UInt32(cc & 0x7F) << 8 | UInt32(value & 0x7F),
                to: device)
    }

    private func send(programChange program: UInt8) {
        sendUMP(0x2000_0000 | (0xC0 | statusChannel(active)) << 16 | UInt32(program & 0x7F) << 8, to: active)
    }

    private func send(realtime status: UInt8, to device: StageDevice? = nil) {
        sendUMP(0x1000_0000 | UInt32(status) << 16, to: device ?? active)
    }

    /// One MIDI 1.0 message as a 32-bit Universal MIDI Packet word, sent to that
    /// device's output only.
    private func sendUMP(_ word: UInt32, to device: StageDevice) {
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        var w = word
        _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &w)
        let target = connection(for: device).destinationID
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            var uid: MIDIUniqueID = 0
            MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uid)
            if target == nil || target == uid {
                MIDISendEventList(outPort, endpoint, &list)
            }
        }
    }

    private func note(_ text: String, device: StageDevice? = nil) {
        let device = device ?? active
        let time = Date.now.formatted(date: .omitted, time: .standard)
        let target = isConnected(device) ? "" : " (ยังไม่ได้ต่อ MIDI)"
        log.insert("\(time)  [\(device.shortName)] \(text)\(target)", at: 0)
        if log.count > 50 { log.removeLast() }
    }
}
