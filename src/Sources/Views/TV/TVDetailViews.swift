// Diapason — tvOS detail pages (album / artist / playlist).
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

#if os(tvOS)
import SwiftUI
import SwiftSonic

// MARK: - Shared header

/// Large hero header: artwork on the left, title/subtitle/meta + Play/Shuffle on the right.
private struct TVDetailHeader: View {
    let coverArtId: String?
    let title: String
    let subtitle: String?
    let meta: String?
    var placeholder: String = "music.note"
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 60) {
            CoverArtView(id: coverArtId ?? "", size: 700, cornerRadius: 16, placeholderSystemImage: placeholder)
                .frame(width: 360, height: 360)
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)

            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.system(size: 56, weight: .bold))
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                if let meta {
                    Text(meta)
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 24) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill").font(.system(size: 26, weight: .semibold))
                            .padding(.horizontal, 12)
                    }
                    Button(action: onShuffle) {
                        Label("Shuffle", systemImage: "shuffle").font(.system(size: 26, weight: .semibold))
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TVMetrics.screenH)
        .padding(.top, TVMetrics.screenTop)
    }
}

// MARK: - Album detail

struct TVAlbumDetailView: View {
    let album: AlbumID3

    @Environment(\.appContainer) private var container
    @State private var songs: [DisplayableSong] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                TVDetailHeader(
                    coverArtId: album.coverArt ?? album.id,
                    title: album.name,
                    subtitle: album.artist,
                    meta: metaLine,
                    onPlay: { play(at: 0) },
                    onShuffle: shuffle
                )

                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        Button { play(at: index) } label: {
                            TVSongRow(index: index, song: song, isCurrent: isCurrent(song))
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, TVMetrics.screenH)
            }
            .padding(.bottom, TVMetrics.railSpacing)
        }
        .navigationTitle(album.name)
        .overlay { if !loaded { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) } }
        .task { await load() }
    }

    private var metaLine: String? {
        var parts: [String] = []
        if let year = album.year { parts.append(String(year)) }
        parts.append("\(album.songCount) songs")
        return parts.joined(separator: " · ")
    }

    private func isCurrent(_ s: DisplayableSong) -> Bool { container?.playerState.currentTrack?.id == s.id }
    private func play(at index: Int) {
        Task { try? await container?.playerService.play(tracks: songs, startIndex: index) }
    }
    private func shuffle() {
        Task { try? await container?.playerService.play(tracks: songs.shuffled(), startIndex: 0) }
    }

    private func load() async {
        if let full = try? await container?.libraryService.album(id: album.id) {
            songs = (full.song ?? []).map { DisplayableSong(from: $0) }
        }
        loaded = true
    }
}

// MARK: - Artist detail

struct TVArtistDetailView: View {
    let artist: ArtistID3

    @Environment(\.appContainer) private var container
    @State private var albums: [AlbumID3] = []
    @State private var loaded = false

    private let columns = [GridItem(.adaptive(minimum: TVMetrics.posterSize + 40), spacing: TVMetrics.cardSpacing)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                TVDetailHeader(
                    coverArtId: artist.coverArt,
                    title: artist.name,
                    subtitle: albums.isEmpty ? nil : "\(albums.count) albums",
                    meta: nil,
                    placeholder: "person.fill",
                    onPlay: playTop,
                    onShuffle: shuffleAll
                )

                if !albums.isEmpty {
                    Text("Albums")
                        .font(.system(size: 34, weight: .bold))
                        .padding(.horizontal, TVMetrics.screenH)
                    LazyVGrid(columns: columns, spacing: TVMetrics.railSpacing) {
                        ForEach(albums) { album in
                            TVPosterLink(value: album, coverArtId: album.coverArt ?? album.id, title: album.name,
                                         subtitle: album.year.map(String.init))
                        }
                    }
                    .padding(.horizontal, TVMetrics.screenH)
                }
            }
            .padding(.bottom, TVMetrics.railSpacing)
        }
        .navigationTitle(artist.name)
        .overlay { if !loaded { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) } }
        .task { await load() }
    }

    private func playTop() {
        Task {
            if let tracks = try? await container?.libraryService.fetchAllTracks(forArtistID: artist.id), !tracks.isEmpty {
                try? await container?.playerService.play(tracks: tracks, startIndex: 0)
            }
        }
    }
    private func shuffleAll() {
        Task {
            if let tracks = try? await container?.libraryService.fetchAllTracks(forArtistID: artist.id), !tracks.isEmpty {
                try? await container?.playerService.play(tracks: tracks.shuffled(), startIndex: 0)
            }
        }
    }

    private func load() async {
        if let full = try? await container?.libraryService.artist(id: artist.id) {
            albums = (full.album ?? []).sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        }
        loaded = true
    }
}

// MARK: - Playlist detail (play-only)

struct TVPlaylistDetailView: View {
    let playlist: Playlist

    @Environment(\.appContainer) private var container
    @State private var songs: [DisplayableSong] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                TVDetailHeader(
                    coverArtId: playlist.coverArt ?? playlist.id,
                    title: playlist.name,
                    subtitle: "\(playlist.songCount) songs",
                    meta: playlist.comment,
                    placeholder: "music.note.list",
                    onPlay: { play(at: 0) },
                    onShuffle: shuffle
                )

                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        Button { play(at: index) } label: {
                            TVSongRow(index: index, song: song, isCurrent: isCurrent(song))
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, TVMetrics.screenH)
            }
            .padding(.bottom, TVMetrics.railSpacing)
        }
        .navigationTitle(playlist.name)
        .overlay { if !loaded { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) } }
        .task { await load() }
    }

    private func isCurrent(_ s: DisplayableSong) -> Bool { container?.playerState.currentTrack?.id == s.id }
    private func play(at index: Int) {
        Task { try? await container?.playerService.play(tracks: songs, startIndex: index) }
    }
    private func shuffle() {
        Task { try? await container?.playerService.play(tracks: songs.shuffled(), startIndex: 0) }
    }

    private func load() async {
        if let full = try? await container?.libraryService.playlist(id: playlist.id) {
            songs = (full.entry ?? []).map { DisplayableSong(from: $0) }
        }
        loaded = true
    }
}
#endif
