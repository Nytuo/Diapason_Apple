import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var backend: BackendManager
    @State private var playlists: [Playlist] = []
    @State private var isLoading = false
    @State private var lastBackendType: BackendType?

    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    ProgressView("Loading Playlists...")
                }
            } else if playlists.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Playlists Found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(playlists) { playlist in
                            NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    PlaylistArtView(playlist: playlist)
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

                                    Text(playlist.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    Text("\(playlist.songCount ?? 0) songs")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    Spacer(minLength: 120) // space for mini player
                }
            }
        }
        .navigationTitle("Playlists")
        .customNavigationBarTitleDisplayMode()
        .background(Color.customSystemGroupedBackground)
        .onAppear { refreshIfNecessary() }
        .onChange(of: backend.activeType) { _ in refreshIfNecessary() }
    }

    private func refreshIfNecessary() {
        if backend.client.isConnected && (playlists.isEmpty || lastBackendType != backend.activeType) {
            lastBackendType = backend.activeType
            Task {
                await MainActor.run { isLoading = true }
                let fetched = (try? await backend.client.getPlaylists()) ?? []
                await MainActor.run {
                    self.playlists = fetched
                    self.isLoading = false
                }
            }
        }
    }
}
