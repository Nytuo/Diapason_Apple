import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var backend: BackendManager
    @EnvironmentObject var player: PlayerManager
    @State private var albums: [Album] = []
    @State private var isLoading = false
    @State private var lastBackendType: BackendType?
    @State private var loadTask: Task<Void, Never>? = nil

    // 2-column grid for iOS mobile screens
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Main Header
                Text("Library")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                    .padding(.top, 10)

                // Navigation List Rows (Apple Music style)
                VStack(spacing: 0) {
                    NavigationLink(destination: PlaylistsView()) {
                        LibraryRow(icon: "music.note.list", title: "Playlists")
                    }
                    Divider().padding(.leading, 52)

                    NavigationLink(destination: ArtistListView()) {
                        LibraryRow(icon: "music.mic", title: "Artists")
                    }
                    Divider().padding(.leading, 52)

                    NavigationLink(destination: AlbumListView()) {
                        LibraryRow(icon: "square.stack", title: "Albums")
                    }
                    Divider().padding(.leading, 52)

                    NavigationLink(destination: LocalFilesView()) {
                        LibraryRow(icon: "folder", title: "Local Files")
                    }
                    Divider().padding(.leading, 52)

                    NavigationLink(destination: DownloadedSongsView()) {
                        LibraryRow(icon: "arrow.down.circle", title: "Downloaded")
                    }
                }
                .background(Color.customSecondarySystemGroupedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Recently Added Section
                if !backend.client.isConnected && !isLoading {
                    VStack(spacing: 16) {
                        Spacer(minLength: 40)
                        Image(systemName: "server.rack")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No Server Connection")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Button("Reconnect") {
                            refreshIfNecessary(force: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: .infinity)
                } else if isLoading {
                    VStack {
                        Spacer(minLength: 40)
                        ProgressView("Loading Library...")
                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    if !albums.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recently Added")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)

                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(albums.prefix(20)) { album in
                                    NavigationLink(destination: AlbumDetailView(album: album)) {
                                        LibraryAlbumGridCard(album: album)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.top, 10)
                    } else {
                        VStack(spacing: 12) {
                            Spacer(minLength: 40)
                            Text("No Albums Found")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 40)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                // Padding to prevent overlap with floating mini player
                Spacer(minLength: 120)
            }
        }
        .background(Color.customSystemGroupedBackground)
        .onAppear { refreshIfNecessary() }
        .onDisappear { loadTask?.cancel() }
        .onChange(of: backend.activeType) { _ in refreshIfNecessary(force: true) }
    }

    func refreshIfNecessary(force: Bool = false) {
        loadTask?.cancel()
        loadTask = Task {
            if !backend.client.isConnected || force {
                await MainActor.run { isLoading = true }
                await backend.autoConnect()
            }
            if backend.client.isConnected && (albums.isEmpty || lastBackendType != backend.activeType || force) {
                await MainActor.run { isLoading = true }
                lastBackendType = backend.activeType
                let fetched = (try? await backend.client.getAlbums()) ?? []
                if !Task.isCancelled {
                    await MainActor.run { self.albums = fetched; self.isLoading = false }
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        }
    }
}

struct LibraryRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.red)
                .frame(width: 24, height: 24)

            Text(title)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

struct LibraryAlbumGridCard: View {
    let album: Album
    @EnvironmentObject var backend: BackendManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DiapasonArtworkView(url: backend.client.getCoverArtURL(id: album.id))
                .scaledToFill()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

            Text(album.displayTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(album.artist)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}
