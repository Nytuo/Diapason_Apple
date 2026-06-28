import SwiftUI

struct ContentView: View {
    @EnvironmentObject var backend: BackendManager
    @EnvironmentObject var player: PlayerManager

    @State private var selectedTab: Int = 0
    @State private var isNowPlayingPresented: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    LibraryView()
                }
                .tabItem {
                    Label("Library", systemImage: "music.note.house.fill")
                }
                .tag(0)

                NavigationStack {
                    DiscoverView()
                }
                .tabItem {
                    Label("Discover", systemImage: "sparkles")
                }
                .tag(1)

                NavigationStack {
                    SearchView()
                }
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(2)

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
            }
            .tint(.red) // Apple Music branding red accent
            
            // Mini Player sitting above the TabBar
            if player.currentSong != nil {
                MiniPlayerBar(onTap: {
                    isNowPlayingPresented = true
                })
                .padding(.horizontal, 16)
                .padding(.bottom, 64) // Float it above the standard tab bar
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            Task {
                await backend.autoConnect()
            }
        }
        .sheet(isPresented: $isNowPlayingPresented) {
            NowPlayingView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
        }
    }
}

struct MiniPlayerBar: View {
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var backend: BackendManager
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            if let song = player.currentSong {
                DiapasonArtworkView(url: backend.client.getCoverArtURL(id: song.albumId))
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 3)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentSong?.title ?? "Not Playing")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(player.currentSong?.artist ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Play/Pause button
            Button(action: {
                player.togglePlayPause()
            }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            // Skip button
            Button(action: {
                player.next()
            }) {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
