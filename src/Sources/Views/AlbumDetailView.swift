import SwiftUI

struct AlbumDetailView: View {
    @EnvironmentObject var backend: BackendManager
    @EnvironmentObject var player: PlayerManager
    let album: Album

    @ObservedObject private var downloadManager = OfflineDownloadManager.shared

    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var addToPlaylistSong: Song? = nil

    var isAlbumDownloaded: Bool {
        !songs.isEmpty && songs.allSatisfy { downloadManager.isDownloaded(songId: $0.id) }
    }

    var isAlbumDownloading: Bool {
        songs.contains { downloadManager.isDownloading(songId: $0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    DiapasonArtworkView(url: backend.client.getCoverArtURL(id: album.id))
                        .scaledToFill()
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)

                    VStack(spacing: 4) {
                        Text(album.displayTitle)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)

                        Text(album.artist)
                            .font(.headline)
                            .foregroundColor(.red)

                        if let year = album.year {
                            Text(String(year))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 16)

                // Play / Shuffle / Download
                HStack(spacing: 12) {
                    Button {
                        guard !songs.isEmpty else { return }
                        player.play(queue: songs, startingAt: 0)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(songs.isEmpty)

                    Button {
                        guard !songs.isEmpty else { return }
                        player.play(queue: songs.shuffled(), startingAt: 0)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(songs.isEmpty)

                    if !album.id.hasPrefix("local_") {
                        Button {
                            if isAlbumDownloaded {
                                for song in songs { downloadManager.deleteDownload(songId: song.id) }
                            } else {
                                for song in songs {
                                    if let url = backend.client.getStreamURL(id: song.id) {
                                        downloadManager.downloadSong(song: song, remoteURL: url)
                                    }
                                }
                            }
                        } label: {
                            if isAlbumDownloading {
                                ProgressView().frame(width: 24, height: 24).padding(10)
                            } else {
                                Image(systemName: isAlbumDownloaded ? "arrow.down.circle.fill" : "arrow.down.circle")
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(songs.isEmpty)
                    }
                }
                .padding(.horizontal)

                // Tracklist
                if isLoading {
                    ProgressView("Loading tracks…").padding(.top, 40)
                } else if songs.isEmpty {
                    Text("No tracks found").foregroundColor(.secondary).padding(.top, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            Button {
                                player.play(queue: songs, startingAt: index)
                            } label: {
                                HStack(spacing: 16) {
                                    if player.currentSong?.id == song.id && player.isPlaying {
                                        Image(systemName: "speaker.wave.3.fill")
                                            .foregroundColor(.red)
                                            .frame(width: 24)
                                    } else {
                                        Text("\(index + 1)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .frame(width: 24, alignment: .trailing)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(song.title)
                                            .font(.body.weight(.medium))
                                            .foregroundColor(player.currentSong?.id == song.id ? .red : .primary)
                                            .lineLimit(1)

                                        if song.artist != album.artist && song.artist != "Unknown Artist" {
                                            Text(song.artist)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer(minLength: 0)

                                    HStack(spacing: 8) {
                                        downloadStateIcon(for: song)

                                        if let dur = song.duration {
                                            Text(formatDuration(dur))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .songContextMenu(
                                song: song,
                                downloadManager: downloadManager,
                                addToPlaylistSong: $addToPlaylistSong
                            )

                            Divider().padding(.leading, 56)
                        }
                    }
                    .background(Color.customSecondarySystemGroupedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                Spacer(minLength: 120)
            }
        }
        .customNavigationBarTitleDisplayMode()
        .background(Color.customSystemGroupedBackground)
        .onAppear { loadSongs() }
        .sheet(item: $addToPlaylistSong) { song in
            PlaylistPickerView(song: song)
        }
    }

    @ViewBuilder
    private func downloadStateIcon(for song: Song) -> some View {
        if song.id.hasPrefix("local_song_") {
            EmptyView()
        } else if downloadManager.isDownloaded(songId: song.id) {
            Button { downloadManager.deleteDownload(songId: song.id) } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        } else if downloadManager.isDownloading(songId: song.id) {
            ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
        } else {
            Button {
                if let url = backend.client.getStreamURL(id: song.id) {
                    downloadManager.downloadSong(song: song, remoteURL: url)
                }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func loadSongs() {
        Task {
            do {
                let details = try await backend.client.getAlbumDetails(id: album.id)
                await MainActor.run {
                    self.songs = details.song
                    self.isLoading = false
                }
            } catch {
                print("Failed to load album: \(error)")
                await MainActor.run { self.isLoading = false }
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
