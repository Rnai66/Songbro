import SwiftUI

/// First screen: SongBro title, rhythm-machine settings, and the way into the songbook.
struct HomeView: View {
    @Environment(StageMIDI.self) private var midi
    @Environment(SongStore.self) private var store
    @State private var openSongbook = false
    @State private var showNuxPanel = false

    /// Same dark navy as the logo artwork, so the logo sits on a seamless banner.
    private static let logoBackground = Color(red: 0.005, green: 0.032, blue: 0.107)

    /// Fades the logo image's edges so its rectangle melts into the banner.
    private static func edgeFade(_ axis: Axis) -> LinearGradient {
        let stops: [Gradient.Stop] = [
            .init(color: .clear, location: 0), .init(color: .black, location: 0.08),
            .init(color: .black, location: 0.92), .init(color: .clear, location: 1),
        ]
        return axis == .horizontal
            ? LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
            : LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Image("SongBroLogo")
                            .resizable()
                            .scaledToFit()
                            .mask(Self.edgeFade(.horizontal))
                            .mask(Self.edgeFade(.vertical))
                            .frame(maxHeight: 260)
                            .accessibilityLabel("SongBro")
                        Text("เนื้อเพลง + คุมจังหวะ \(midi.active.name)")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .listRowBackground(Self.logoBackground)
                }

                DeviceSettingsSections(openNuxPanel: { showNuxPanel = true })
                AISettingsSection()
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    openSongbook = true
                } label: {
                    Label("เปิดเพลง · \(store.songs(in: nil).count) เพลง", systemImage: "music.note.list")
                        .font(.title3.bold())
                        .frame(maxWidth: 520)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showNuxPanel) {
            NUXControlView().pageSizedSheet()
        }
        .fullScreenCover(isPresented: $openSongbook) {
            ContentView(onHome: { openSongbook = false })
        }
    }
}
