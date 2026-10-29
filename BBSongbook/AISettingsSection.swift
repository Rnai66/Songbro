import SwiftUI

/// Gemini API key and model for the AI beat search.
struct AISettingsSection: View {
    @Environment(AIBeatFinder.self) private var ai
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        @Bindable var ai = ai

        Section {
            SecureField("Gemini API key", text: $ai.apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Text("รุ่น")
                TextField(AIBeatFinder.defaultModel, text: $ai.model)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("ทดสอบ key", systemImage: "checkmark.seal") { test() }
                    .disabled(!ai.hasKey || testing)
                Spacer()
                if testing { ProgressView() }
                if let testResult {
                    Text(testResult).font(.caption).foregroundStyle(testResult.hasPrefix("✓") ? .green : .red)
                }
            }
        } header: {
            Text("AI ค้นหาจังหวะ")
        } footer: {
            Text("สร้าง key ได้ที่ aistudio.google.com › Get API key · key เก็บไว้ใน Keychain ของ iPad เท่านั้น · ใช้ได้จากปุ่ม ✨ ในหน้าเลือกจังหวะ หรือ ✨ เหนือรายการเพลง (ค้นทุกเพลงที่ยังไม่มีจังหวะ) · ผลที่ได้มีเครื่องหมาย ≈ จนกว่าจะกดบันทึกเอง")
        }
    }

    private func test() {
        testing = true
        testResult = nil
        Task {
            do {
                _ = try await ai.testKey()
                testResult = "✓ ใช้ได้"
            } catch {
                testResult = error.localizedDescription
            }
            testing = false
        }
    }
}
