// Pretend to be a BeatBuddy and a NUX Dual Loop Stereo on this Mac, so SongBro
// can be tested without the real pedals.
//
//   swift tools/stage_emulator.swift
//
// It creates two virtual MIDI outputs — "SongBro Test BeatBuddy" and
// "SongBro Test NUX" — which the iOS Simulator sees, and also listens to every
// MIDI source (e.g. a Network MIDI session with the iPad). Each command is
// printed in words, and Start plays a metronome click at the current BPM.
import AVFoundation
import CoreMIDI
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - Beat names from BBManager (same file the app bundles)

struct Folder: Decodable { var number: Int; var name: String; var beats: [Beat] }
struct Beat: Decodable { var number: Int; var name: String }
struct Catalog: Decodable { var folders: [Folder] }

let catalogURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("BBSongbook/Resources/beats.json")
let catalog = (try? JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL)))
    ?? Catalog(folders: [])

func beatName(folder: Int, beat: Int) -> String {
    guard let f = catalog.folders.first(where: { $0.number == folder }) else {
        return "โฟลเดอร์ \(folder) จังหวะ \(beat)"
    }
    let b = f.beats.first { $0.number == beat }?.name ?? "#\(beat)"
    return "\(f.number). \(f.name) › \(beat). \(b)"
}

// MARK: - Metronome

final class Metronome {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let accent: AVAudioPCMBuffer
    private let tick: AVAudioPCMBuffer
    private var timer: DispatchSourceTimer?
    private var beat = 0
    private(set) var running = false
    var bpm = 100 { didSet { if running { start() } } }

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        func click(_ freq: Double) -> AVAudioPCMBuffer {
            let frames = AVAudioFrameCount(44_100 * 0.04)
            let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buf.frameLength = frames
            for i in 0..<Int(frames) {
                let t = Double(i) / 44_100
                buf.floatChannelData![0][i] = Float(sin(2 * .pi * freq * t) * exp(-t * 90) * 0.8)
            }
            return buf
        }
        accent = click(1_800)
        tick = click(1_100)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try? engine.start()
        player.play()
    }

    func start() {
        timer?.cancel()
        running = true
        beat = 0
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 60.0 / Double(max(bpm, 1)), leeway: .milliseconds(1))
        t.setEventHandler { [unowned self] in
            player.scheduleBuffer(beat % 4 == 0 ? accent : tick, at: nil)
            beat += 1
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        running = false
    }
}

let metronome = Metronome()

func log(_ device: String, _ text: String) {
    let time = Date().formatted(date: .omitted, time: .standard)
    print("\(time)  \(device) ← \(text)")
}

// MARK: - BeatBuddy

final class BeatBuddyState {
    var bankMSB = 0, bankLSB = 0, tempoMSB = 0

    func handle(status: UInt8, d1: UInt8, d2: UInt8) {
        switch status & 0xF0 {
        case 0xB0:
            switch d1 {
            case 0: bankMSB = Int(d2)
            case 32: bankLSB = Int(d2)
            case 106: tempoMSB = Int(d2)
            case 107:
                metronome.bpm = tempoMSB << 7 | Int(d2)
                log("BeatBuddy", "BPM \(metronome.bpm)")
            case 113: log("BeatBuddy", d2 == 0 ? "ปล่อย Transition → ท่อนถัดไป" : "Transition เริ่ม (ค้างไว้)")
            case 112: log("BeatBuddy", "Fill")
            case 111: log("BeatBuddy", "Pause/ต่อ")
            default: log("BeatBuddy", "CC \(d1) = \(d2) (ไม่รู้จัก)")
            }
        case 0xC0:
            let folder = (bankMSB << 7 | bankLSB) + 1
            log("BeatBuddy", "เลือกจังหวะ \(beatName(folder: folder, beat: Int(d1) + 1))")
        default:
            log("BeatBuddy", String(format: "ข้อความ %02X %d %d", status, d1, d2))
        }
    }
}

// MARK: - NUX Dual Loop Stereo (CC table from the owner's manual)

final class NuxState {
    func handle(status: UInt8, d1: UInt8, d2: UInt8) {
        guard status & 0xF0 == 0xB0 else {
            return log("NUX", String(format: "ข้อความ %02X %d %d", status, d1, d2))
        }
        switch d1 {
        case 11: log("NUX", String(format: "โหลด Memory %02d", d2))
        case 30:
            metronome.running ? metronome.stop() : metronome.start()
            log("NUX", metronome.running ? "กลอง เปิด ▶︎" : "กลอง ปิด ■")
        case 37: metronome.bpm = Int(d2); log("NUX", "BPM \(metronome.bpm)")
        case 38: metronome.bpm = Int(d2) + 100; log("NUX", "BPM \(metronome.bpm)")
        case 39: metronome.bpm = Int(d2) + 200; log("NUX", "BPM \(metronome.bpm)")
        default: log("NUX", "CC \(d1) = \(d2)")
        }
    }
}

let beatBuddy = BeatBuddyState()
let nux = NuxState()

/// Walks a MIDI 1.0 UMP event list and hands each message to `handle`.
func forEachMessage(_ list: UnsafePointer<MIDIEventList>, _ handle: (UInt8, UInt8, UInt8) -> Void) {
    for packet in list.unsafeSequence() {
        for word in packet.words() {
            switch word >> 28 {
            case 0x1: // system realtime (Start FA / Stop FC / Clock F8)
                handle(UInt8(word >> 16 & 0xFF), 0, 0)
            case 0x2: // MIDI 1.0 channel voice
                handle(UInt8(word >> 16 & 0xFF), UInt8(word >> 8 & 0x7F), UInt8(word & 0x7F))
            default:
                break
            }
        }
    }
}

func beatBuddyMessage(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) {
    switch status {
    case 0xFA: metronome.start(); log("BeatBuddy", "Start ▶︎")
    case 0xFC: metronome.stop(); log("BeatBuddy", "Stop ■")
    case 0xF8: break
    default: beatBuddy.handle(status: status, d1: d1, d2: d2)
    }
}

// MARK: - MIDI endpoints

var client = MIDIClientRef()
var inPort = MIDIPortRef()
var connectedSources = Set<MIDIUniqueID>()

/// Listen to every source, including ones that appear later (the iPad joining
/// the Network MIDI session).
func connectAllSources() {
    for i in 0..<MIDIGetNumberOfSources() {
        let source = MIDIGetSource(i)
        var uid: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uid)
        guard !connectedSources.contains(uid) else { continue }
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name)
        if MIDIPortConnectSource(inPort, source, nil) == noErr {
            connectedSources.insert(uid)
            print("ฟัง MIDI จาก: \(name?.takeRetainedValue() as String? ?? "?")")
        }
    }
}

MIDIClientCreateWithBlock("SongBro Test" as CFString, &client) { _ in
    DispatchQueue.main.async { connectAllSources() }
}

var bbDest = MIDIEndpointRef()
MIDIDestinationCreateWithProtocol(client, "SongBro Test BeatBuddy" as CFString, ._1_0, &bbDest) { list, _ in
    forEachMessage(list) { s, a, b in DispatchQueue.main.async { beatBuddyMessage(s, a, b) } }
}

var nuxDest = MIDIEndpointRef()
MIDIDestinationCreateWithProtocol(client, "SongBro Test NUX" as CFString, ._1_0, &nuxDest) { list, _ in
    forEachMessage(list) { s, a, b in DispatchQueue.main.async { nux.handle(status: s, d1: a, d2: b) } }
}

// Anything arriving from a real source (e.g. the iPad over Network MIDI) is
// decoded as BeatBuddy, or as NUX when it uses the NUX-only CC numbers.
// The Network MIDI session shows up as two sources ("iPad" and "Network Session 1"),
// so each message arrives twice. Drop an identical copy within 50 ms — otherwise
// NUX's on/off toggle (CC 30) would switch the drum straight back off.
var lastMessage: (status: UInt8, d1: UInt8, d2: UInt8, at: Date)?
func isDuplicate(_ s: UInt8, _ a: UInt8, _ b: UInt8) -> Bool {
    defer { lastMessage = (s, a, b, Date()) }
    guard let last = lastMessage else { return false }
    return last.status == s && last.d1 == a && last.d2 == b && Date().timeIntervalSince(last.at) < 0.05
}

MIDIInputPortCreateWithProtocol(client, "SongBro Test In" as CFString, ._1_0, &inPort) { list, _ in
    forEachMessage(list) { s, a, b in
        DispatchQueue.main.async {
            guard !isDuplicate(s, a, b) else { return }
            if s & 0xF0 == 0xB0, [11, 30, 37, 38, 39].contains(a) {
                nux.handle(status: s, d1: a, d2: b)
            } else {
                beatBuddyMessage(s, a, b)
            }
        }
    }
}
connectAllSources()

// Turn on this Mac's Wi-Fi MIDI session so the iPad can join it.
MIDINetworkSession.default().isEnabled = true
MIDINetworkSession.default().connectionPolicy = .anyone

/// Finds other Network MIDI sessions on the Wi-Fi (SongBro on the iPad
/// advertises one) and connects to them, so no Audio MIDI Setup clicks are needed.
final class SessionFinder: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var pending: [NetService] = []

    func start() {
        browser.delegate = self
        browser.searchForServices(ofType: "_apple-midi._udp", inDomain: "local.")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard service.name != MIDINetworkSession.default().localName else { return }
        pending.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ service: NetService) {
        let session = MIDINetworkSession.default()
        guard !session.connections().contains(where: { $0.host.name == service.name }) else { return }
        let host = MIDINetworkHost(name: service.name, netService: service)
        if session.addConnection(MIDINetworkConnection(host: host)) {
            print("เชื่อม Wi-Fi MIDI กับ: \(service.name)")
            connectAllSources()
        }
    }
}

let finder = SessionFinder()
finder.start()

print("พร้อมแล้ว · Mac นี้เปิด Network MIDI ชื่อ \"\(MIDINetworkSession.default().networkName)\" แล้ว")
print("ส่งจาก SongBro บน iPad ผ่าน Wi-Fi ได้เลย · กด Ctrl+C เพื่อปิด")
RunLoop.main.run()
