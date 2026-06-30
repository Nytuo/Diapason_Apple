import SwiftUI

struct DiscoveryPlaylistView: View {
    let playlistId: String

    @EnvironmentObject var player: PlayerManager
    @ObservedObject private var feed = DiscoveryFeedManager.shared
    @ObservedObject private var downloadManager = OfflineDownloadManager.shared

    private var playlist: DiscoveryPlaylist? {
        feed.playlists.first(where: { $0.id == playlistId })
    }

    var body: some View {
        List {
            if let playlist {
                if !playlist.tracks.isEmpty {
                    Section {
                        Button {
                            Task { await feed.downloadAll(playlist) }
                        } label: {
                            Label("Download all", systemImage: "arrow.down.circle")
                        }
                    }
                }
                ForEach(playlist.tracks) { track in
                    row(playlist: playlist, track: track)
                }
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .task { await feed.loadTracks(playlistId: playlistId) }
    }

    @ViewBuilder
    private func row(playlist: DiscoveryPlaylist, track: DiscoveryTrack) -> some View {
        let isDownloaded = downloadManager.isDownloaded(songId: track.id)
        let isDownloading = downloadManager.isDownloading(songId: track.id)
        let isResolving = feed.resolvingIds.contains(track.id)

        Button {
            if isDownloaded {
                let songs = feed.downloadedSongs(in: playlist)
                let idx = songs.firstIndex(where: { $0.id == track.id }) ?? 0
                player.play(queue: songs, startingAt: idx)
            } else if !isDownloading && !isResolving {
                Task { await feed.download(track) }
            }
        } label: {
            HStack(spacing: 12) {
                CoverArt(urlString: track.coverURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.body).lineLimit(1)
                    Text(track.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                if isDownloaded {
                    Image(systemName: "play.circle.fill").foregroundColor(.accentColor)
                } else if isDownloading || isResolving {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.circle").foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CoverArt: View {
    let urlString: String?
    var body: some View {
        AsyncImage(url: urlString.flatMap(URL.init(string:))) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Image(systemName: "music.note").foregroundColor(.secondary)
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
