import CoreAudioKit
import CoreMIDI
import SwiftUI

/// MIDI settings opened from the song list (same content as the home screen).
struct MIDISettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DeviceSettingsSections()
            }
            .navigationTitle("อุปกรณ์ MIDI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("เสร็จ") { dismiss() }
            }
        }
    }
}

/// Pick the active rhythm machine (BeatBuddy / NUX), its MIDI output and channel,
/// the NUX command numbers, plus test buttons and a log of what was sent.
struct DeviceSettingsSections: View {
    @Environment(StageMIDI.self) private var midi
    @State private var showBluetooth = false

    var body: some View {
        @Bindable var midi = midi

        Section {
            Picker("อุปกรณ์", selection: $midi.active) {
                ForEach(StageDevice.allCases) { device in
                    Label(device.shortName, systemImage: device.icon).tag(device)
                }
            }
            .pickerStyle(.segmented)
            ForEach(StageDevice.allCases) { device in
                HStack {
                    Label(device.name, systemImage: device.icon)
                    Spacer()
                    if device == midi.active {
                        Text("ใช้งานอยู่").font(.caption.bold()).foregroundStyle(.tint)
                    }
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(midi.isConnected(device) ? .green : .secondary)
                }
            }
        } header: {
            Text("อุปกรณ์ที่ใช้งาน")
        } footer: {
            Text("สลับได้ตลอดเวลา แต่ละอุปกรณ์จำช่อง MIDI และ Channel ของตัวเองไว้ จุดสีเขียว = ต่ออยู่")
        }

        Section {
            if midi.destinations.isEmpty {
                Label("ยังไม่พบอุปกรณ์ MIDI", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Picker("ส่งไปที่", selection: connectionBinding(\.destinationID)) {
                Text("ทุกช่อง MIDI").tag(MIDIUniqueID?.none)
                ForEach(midi.destinations) { d in
                    Text(d.name).tag(MIDIUniqueID?.some(d.id))
                }
            }
            Stepper("MIDI Channel \(midi.connection(for: midi.active).channel)",
                    value: connectionBinding(\.channel), in: 1...16)
            Button("ค้นหาอุปกรณ์ใหม่", systemImage: "arrow.clockwise") { midi.refresh() }
            Button("เชื่อมต่อ Bluetooth MIDI (WIDI)", systemImage: "dot.radiowaves.left.and.right") {
                showBluetooth = true
            }
        } header: {
            Text("การเชื่อมต่อ \(midi.active.shortName)")
        } footer: {
            Text("ถ้าต่อทั้งสองเครื่องพร้อมกัน ให้เลือกช่อง MIDI ของแต่ละเครื่องแยกกัน คำสั่งจะได้ไม่ไปผิดเครื่อง\nChannel ต้องตรงกับที่ตั้งไว้ในเมนู MIDI ของเครื่องนั้น")
        }

        if midi.active == .nuxDualLoop {
            Section {
                LabeledContent("เลือก Memory 01–99", value: "CC 11")
                LabeledContent("Tempo 30–250 BPM", value: "CC 37 / 38 / 39")
                LabeledContent("กลอง เปิด/ปิด", value: "CC 30")
                Button("สลับกลอง เปิด/ปิด", systemImage: "arrow.left.arrow.right") { midi.toggleNuxDrum() }
            } header: {
                Text("คำสั่ง MIDI ของ NUX (จากคู่มือ)")
            } footer: {
                Text("ตั้งค่าตามตาราง MIDI Control ในคู่มือ NML-3DLS แล้ว ไม่ต้องใส่เอง · NUX ไม่มีคำสั่ง Fill และเปลี่ยนท่อน · กลองของ NUX เป็นปุ่มสลับ ถ้าเหยียบที่เครื่องเองแล้วแอปกับเครื่องไม่ตรงกัน กด \"สลับกลอง\" หนึ่งครั้ง")
            }
        }

        Section("ทดสอบ \(midi.active.shortName)") {
            HStack {
                Button("Start") { midi.start() }
                Button("Stop") { midi.stop() }
                Button(midi.paused ? "ต่อ" : "Pause") { midi.togglePause() }
                    .disabled(!midi.supportsFillAndParts)
                Button("Fill") { midi.fill() }
                    .disabled(!midi.supportsFillAndParts)
                Button("ท่อนถัดไป") { midi.nextPart() }
                    .disabled(!midi.supportsFillAndParts)
            }
            .buttonStyle(.bordered)
        }

        Section("คำสั่งที่ส่งล่าสุด") {
            if midi.log.isEmpty {
                Text("ยังไม่มี").foregroundStyle(.secondary)
            }
            ForEach(Array(midi.log.enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption.monospaced())
            }
        }
        .sheet(isPresented: $showBluetooth, onDismiss: { midi.refresh() }) {
            NavigationStack {
                BluetoothMIDIPicker()
                    .navigationTitle("Bluetooth MIDI")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("เสร็จ") { showBluetooth = false } }
            }
        }
    }

    /// Edits one field of the active device's connection.
    private func connectionBinding<T>(_ keyPath: WritableKeyPath<DeviceConnection, T>) -> Binding<T> {
        Binding {
            midi.connection(for: midi.active)[keyPath: keyPath]
        } set: { value in
            var connection = midi.connection(for: midi.active)
            connection[keyPath: keyPath] = value
            midi.setConnection(connection, for: midi.active)
        }
    }
}

/// Apple's built-in Bluetooth LE MIDI pairing screen.
struct BluetoothMIDIPicker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CABTMIDICentralViewController {
        CABTMIDICentralViewController()
    }

    func updateUIViewController(_ controller: CABTMIDICentralViewController, context: Context) {}
}
