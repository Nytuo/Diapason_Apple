import SwiftUI

// MARK: - Reusable Song Context Menu

/// Provides a standardised long-press / context-menu set of actions for any Song row.
/// Usage:  someView.songContextMenu(song: song, player: player, downloadManager: dm)
struct SongContextMenuContent: View {
    let song: Song
    @EnvironmentObject var backend: BackendManager
    @EnvironmentObject var player: PlayerManager
    @ObservedObject var downloadManager: OfflineDownloadManager

    @Binding var addToPlaylistSong: Song?

    var body: some View {
        Group {
            // Play Next
            Button {
                let insertIdx = player.currentIndex + 1
                var q = player.queue
                if insertIdx < q.count {
                    q.insert(song, at: insertIdx)
                } else {
                    q.append(song)
                }
                player.queue = q
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            // Add to Queue
            Button {
                player.queue.append(song)
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }

            Divider()

            // Add to Playlist
            if !song.id.hasPrefix("local_song_") {
                Button {
                    addToPlaylistSong = song
                } label: {
                    Label("Add to Playlist…", systemImage: "music.note.list")
                }
                Divider()
            }

            // Download / Remove download
            if !song.id.hasPrefix("local_song_") {
                if downloadManager.isDownloaded(songId: song.id) {
                    Button(role: .destructive) {
                        downloadManager.deleteDownload(songId: song.id)
                    } label: {
                        Label("Remove Download", systemImage: "trash")
                    }
                } else if downloadManager.isDownloading(songId: song.id) {
                    Label("Downloading…", systemImage: "arrow.down.circle")
                } else {
                    Button {
                        if let url = backend.client.getStreamURL(id: song.id) {
                            downloadManager.downloadSong(song: song, remoteURL: url)
                        }
                    } label: {
                        Label("Download Offline", systemImage: "arrow.down.circle")
                    }
                }
            }
        }
    }
}

// MARK: - View Modifier

struct SongRowContextMenu: ViewModifier {
    let song: Song
    @EnvironmentObject var backend: BackendManager
    @EnvironmentObject var player: PlayerManager
    @ObservedObject var downloadManager: OfflineDownloadManager
    @Binding var addToPlaylistSong: Song?

    func body(content: Content) -> some View {
        content.contextMenu {
            SongContextMenuContent(
                song: song,
                downloadManager: downloadManager,
                addToPlaylistSong: $addToPlaylistSong
            )
            .environmentObject(backend)
            .environmentObject(player)
        }
    }
}

extension View {
    func songContextMenu(
        song: Song,
        downloadManager: OfflineDownloadManager,
        addToPlaylistSong: Binding<Song?>
    ) -> some View {
        modifier(SongRowContextMenu(
            song: song,
            downloadManager: downloadManager,
            addToPlaylistSong: addToPlaylistSong
        ))
    }
}
