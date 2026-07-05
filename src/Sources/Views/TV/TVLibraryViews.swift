// Diapason — tvOS dedicated library pages (grids + song list).
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

#if os(tvOS)
import SwiftUI
import SwiftSonic

private enum TVGrid {
    static let albumColumns = [GridItem(.adaptive(minimum: TVMetrics.posterSize + 40), spacing: TVMetrics.cardSpacing)]
    static let artistColumns = [GridItem(.adaptive(minimum: TVMetrics.artistSize + 60), spacing: TVMetrics.cardSpacing)]
}

// MARK: - Albums (all / recently added)

struct TVAlbumsView: View {
    enum Source { case all, recentlyAdded }
    let source: Source

    @Environment(\.appContainer) private var container
    @State private var albums: [AlbumID3] = []
    @State private var loaded = false

    private var title: String { source == .recentlyAdded ? "Recently Added" : "Albums" }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: TVGrid.albumColumns, spacing: TVMetrics.railSpacing) {
                ForEach(albums) { album in
                    TVPosterLink(value: album, coverArtId: album.coverArt ?? album.id, title: album.name, subtitle: album.artist)
                }
            }
            .padding(.horizontal, TVMetrics.screenH)
            .padding(.vertical, TVMetrics.screenTop)
        }
        .navigationTitle(title)
        .overlay { if !loaded { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) } }
        .task { await load() }
    }

    private func load() async {
        guard let lib = container?.libraryService else { return }
        switch source {
        case .all:           albums = (try? await lib.allAlbums()) ?? []
        case .recentlyAdded: albums = (try? await lib.recentlyAddedAlbums(size: 100)) ?? []
        }
        loaded = true
    }
}

// MARK: - Artists

struct TVArtistsView: View {
    @Environment(\.appContainer) private var container
    @State private var artists: [ArtistID3] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: TVGrid.artistColumns, spacing: TVMetrics.railSpacing) {
                ForEach(artists) { artist in
                    TVArtistLink(value: artist, coverArtId: artist.coverArt, name: artist.name)
                }
            }
            .padding(.horizontal, TVMetrics.screenH)
            .padding(.vertical, TVMetrics.screenTop)
        }
        .navigationTitle("Artists")
        .overlay { if !loaded { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) } }
        .task { await load() }
    }

    private func load() async {
        guard let lib = container?.libraryService else { return }
        let index = (try? await lib.artists()) ?? []
        artists = index.flatMap { $0.artist }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        loaded = true
    }
}

// MARK: - Songs

struct TVSongsView: View {
    @Environment(\.appContainer) private var container
    @State private var songs: [DisplayableSong] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    Button { play(at: index) } label: {
                        TVSongRow(index: index, song: song, isCurrent: isCurrent(song))
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, TVMetrics.screenH)
            .padding(.vertical, TVMetrics.screenTop)
        }
        .navigationTitle("Songs")
        .overlay { if !loaded { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) } }
        .task { await load() }
    }

    private func isCurrent(_ s: DisplayableSong) -> Bool { container?.playerState.currentTrack?.id == s.id }
    private func play(at index: Int) {
        Task { try? await container?.playerService.play(tracks: songs, startIndex: index) }
    }

    private func load() async {
        guard let lib = container?.libraryService else { return }
        let random = (try? await lib.randomSongs(size: 500)) ?? []
        songs = random.map { DisplayableSong(from: $0) }
            .sorted {
                ($0.artist ?? "", $0.albumName ?? "", $0.trackNumber ?? 0, $0.title)
                    < ($1.artist ?? "", $1.albumName ?? "", $1.trackNumber ?? 0, $1.title)
            }
        loaded = true
    }
}

// MARK: - Playlists

struct TVPlaylistsView: View {
    @Environment(\.appContainer) private var container
    @State private var playlists: [Playlist] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: TVGrid.albumColumns, spacing: TVMetrics.railSpacing) {
                ForEach(playlists) { playlist in
                    TVPosterLink(value: playlist, coverArtId: playlist.coverArt ?? playlist.id, title: playlist.name,
                                 subtitle: "\(playlist.songCount) songs", placeholder: "music.note.list")
                }
            }
            .padding(.horizontal, TVMetrics.screenH)
            .padding(.vertical, TVMetrics.screenTop)
        }
        .navigationTitle("Playlists")
        .overlay {
            if loaded && playlists.isEmpty {
                ContentUnavailableView("No Playlists", systemImage: "music.note.list")
            } else if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
    }

    private func load() async {
        playlists = (try? await container?.libraryService.playlists()) ?? []
        loaded = true
    }
}
#endif
