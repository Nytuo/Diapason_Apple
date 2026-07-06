// Diapason — tvOS Home (horizontal rails + dedicated pages).
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

#if os(tvOS)
import SwiftUI
import SwiftSonic

struct TVHomeView: View {
    @Environment(\.appContainer) private var container

    @State private var recentlyAdded: [AlbumID3] = []
    @State private var albums: [AlbumID3] = []
    @State private var artists: [ArtistID3] = []
    @State private var songs: [DisplayableSong] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVMetrics.railSpacing) {
                if !recentlyAdded.isEmpty {
                    TVRail(title: "Recently Added", items: recentlyAdded, seeAll: .recentlyAdded) { album in
                        TVPosterLink(value: album, coverArtId: album.coverArt ?? album.id, title: album.name, subtitle: album.artist)
                    }
                }

                if !artists.isEmpty {
                    TVRail(title: "Artists", items: Array(artists.prefix(18)), seeAll: .artists) { artist in
                        TVArtistLink(value: artist, coverArtId: artist.coverArt, name: artist.name)
                    }
                }

                if !albums.isEmpty {
                    TVRail(title: "Albums", items: albums, seeAll: .albums) { album in
                        TVPosterLink(value: album, coverArtId: album.coverArt ?? album.id, title: album.name, subtitle: album.artist)
                    }
                }

                if !songs.isEmpty {
                    songsRail
                }
            }
            .padding(.top, TVMetrics.screenTop)
            .padding(.bottom, TVMetrics.railSpacing)
        }
        .navigationTitle("Home")
        .overlay {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
    }

    private var songsRail: some View {
        VStack(alignment: .leading, spacing: 24) {
            TVSectionHeader(title: "Songs") {
                NavigationLink(value: TVLibrarySection.songs) {
                    HStack(spacing: 6) { Text("See All"); Image(systemName: "chevron.right") }
                        .font(.system(size: 24, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accent)
            }
            .padding(.horizontal, TVMetrics.screenH)

            LazyVStack(spacing: 0) {
                ForEach(Array(songs.prefix(6).enumerated()), id: \.element.id) { index, song in
                    Button {
                        play(songs, at: index)
                    } label: {
                        TVSongRow(index: index, song: song, isCurrent: isCurrent(song))
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, TVMetrics.screenH)
        }
    }

    private func isCurrent(_ song: DisplayableSong) -> Bool {
        container?.playerState.currentTrack?.id == song.id
    }

    private func play(_ tracks: [DisplayableSong], at index: Int) {
        Task { try? await container?.playerService.play(tracks: tracks, startIndex: index) }
    }

    private func load() async {
        guard let lib = container?.libraryService else { return }
        async let recent = try? lib.recentlyAddedAlbums(size: 18)
        async let all = try? lib.allAlbums()
        async let idx = try? lib.artists()
        async let rnd = try? lib.randomSongs(size: 40)

        let recentAlbums = await recent ?? []
        let allAlbums = await all ?? []
        let artistIndex = await idx ?? []
        let randomSongs = await rnd ?? []

        recentlyAdded = recentAlbums
        albums = Array(allAlbums.prefix(18))
        artists = artistIndex.flatMap { $0.artist }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        songs = randomSongs.map { DisplayableSong(from: $0) }
        loaded = true
    }
}
#endif
