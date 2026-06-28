import SwiftUI

struct DownloadedAlbum: Identifiable {
    var id: String { albumId }
    let albumId: String
    let albumName: String
    let artistName: String
    let coverArtId: String
    var songs: [Song]
}

struct DownloadedSongsView: View {
    @ObservedObject var downloadManager = OfflineDownloadManager.shared
    @EnvironmentObject var player: PlayerManager

    var downloadedAlbums: [DownloadedAlbum] {
        var groups: [String: [Song]] = [:]
        for song in downloadManager.downloadedSongs {
            groups[song.albumId, default: []].append(song)
        }
        return groups.map { albumId, songs in
            let sample = songs.first!
            return DownloadedAlbum(
                albumId: albumId,
                albumName: sample.album,
                artistName: sample.artist,
                coverArtId: sample.albumId,
                songs: songs.sorted { ($0.track ?? 0) < ($1.track ?? 0) }
            )
        }.sorted { $0.albumName.localizedCaseInsensitiveCompare($1.albumName) == .orderedAscending }
    }

    var body: some View {
        Group {
            if downloadedAlbums.isEmpty && downloadManager.downloadedPlaylists.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Downloads Yet")
                        .font(.title3.weight(.bold))
                    Text("Long-press on songs in albums or playlists to download them for offline listening.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                List {
                    if !downloadedAlbums.isEmpty {
                        Section("Albums") {
                            ForEach(downloadedAlbums) { album in
                                NavigationLink(destination: DownloadedAlbumDetailView(album: album)) {
                                    HStack(spacing: 16) {
                                        DiapasonArtworkView(url: downloadManager.getDownloadedCoverArtURL(forAlbumId: album.coverArtId))
                                            .scaledToFill()
                                            .frame(width: 56, height: 56)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(album.albumName)
                                                .font(.body.weight(.medium))
                                                .lineLimit(1)
                                            Text(album.artistName)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                            Text("\(album.songs.count) track\(album.songs.count == 1 ? "" : "s")")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        for song in album.songs {
                                            downloadManager.deleteDownload(songId: song.id)
                                        }
                                    } label: {
                                        Label("Delete All", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    if !downloadManager.downloadedPlaylists.isEmpty {
                        Section("Playlists") {
                            ForEach(downloadManager.downloadedPlaylists) { playlist in
                                NavigationLink(destination: DownloadedPlaylistDetailView(playlist: playlist)) {
                                    HStack(spacing: 16) {
                                        DiapasonArtworkView(url: playlist.coverArtId.flatMap { downloadManager.getDownloadedCoverArtURL(forAlbumId: $0) })
                                            .scaledToFill()
                                            .frame(width: 56, height: 56)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(playlist.name)
                                                .font(.body.weight(.medium))
                                                .lineLimit(1)
                                            Text("\(playlist.songIds.count) track\(playlist.songIds.count == 1 ? "" : "s")")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        // Remove all songs in the playlist from downloads
                                        for id in playlist.songIds {
                                            downloadManager.deleteDownload(songId: id)
                                        }
                                        downloadManager.deleteDownloadedPlaylist(id: playlist.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.grouped)
            }
        }
        .navigationTitle("Downloads")
        .background(Color.customSystemGroupedBackground)
    }
}

// MARK: - Downloaded Album Detail

struct DownloadedAlbumDetailView: View {
    let album: DownloadedAlbum
    @EnvironmentObject var player: PlayerManager
    @ObservedObject private var downloadManager = OfflineDownloadManager.shared

    /// Always use fresh songs from the download manager (not stale album.songs)
    var liveSongs: [Song] {
        downloadManager.downloadedSongs
            .filter { $0.albumId == album.albumId }
            .sorted { ($0.track ?? 0) < ($1.track ?? 0) }
    }

    var body: some View {
        List {
            // Play all header
            Section {
                Button {
                    guard !liveSongs.isEmpty else { return }
                    player.play(queue: liveSongs, startingAt: 0)
                } label: {
                    Label("Play All", systemImage: "play.fill")
                        .foregroundColor(.red)
                        .fontWeight(.semibold)
                }
            }

            Section("Tracks — \(liveSongs.count) offline") {
                ForEach(Array(liveSongs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        player.play(queue: liveSongs, startingAt: index)
                    } label: {
                        HStack(spacing: 16) {
                            Text("\(index + 1)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(width: 24, alignment: .trailing)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.body.weight(.medium))
                                    .foregroundColor(player.currentSong?.id == song.id ? .red : .primary)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            if let dur = song.duration {
                                Text(formatDuration(dur))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if player.currentSong?.id == song.id && player.isPlaying {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            downloadManager.deleteDownload(songId: song.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(album.albumName)
        .listStyle(.insetGrouped)
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Downloaded Playlist Detail

struct DownloadedPlaylistDetailView: View {
    let playlist: DownloadedPlaylistRecord
    @EnvironmentObject var player: PlayerManager
    @ObservedObject private var downloadManager = OfflineDownloadManager.shared

    /// Resolve playlist song IDs → live Song objects from download manager
    var liveSongs: [Song] {
        playlist.songIds.compactMap { songId in
            downloadManager.downloadedSongs.first(where: { $0.id == songId })
        }
    }

    var body: some View {
        List {
            // Play all header
            Section {
                Button {
                    guard !liveSongs.isEmpty else { return }
                    player.play(queue: liveSongs, startingAt: 0)
                } label: {
                    Label("Play All", systemImage: "play.fill")
                        .foregroundColor(.red)
                        .fontWeight(.semibold)
                }
            }

            Section("Tracks — \(liveSongs.count) offline") {
                if liveSongs.isEmpty {
                    Text("No downloaded songs in this playlist.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(Array(liveSongs.enumerated()), id: \.element.id) { index, song in
                        Button {
                            player.play(queue: liveSongs, startingAt: index)
                        } label: {
                            HStack(spacing: 16) {
                                Text("\(index + 1)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, alignment: .trailing)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.body.weight(.medium))
                                        .foregroundColor(player.currentSong?.id == song.id ? .red : .primary)
                                        .lineLimit(1)
                                    Text(song.artist)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                if let dur = song.duration {
                                    Text(formatDuration(dur))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if player.currentSong?.id == song.id && player.isPlaying {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                downloadManager.deleteDownload(songId: song.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(playlist.name)
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    for id in playlist.songIds { downloadManager.deleteDownload(songId: id) }
                    downloadManager.deleteDownloadedPlaylist(id: playlist.id)
                } label: {
                    Image(systemName: "trash").foregroundColor(.red)
                }
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
