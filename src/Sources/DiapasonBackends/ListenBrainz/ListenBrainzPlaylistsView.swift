// Diapason — ListenBrainz read-only playlists in Discover.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct ListenBrainzPlaylistsSection: View {
    @Environment(\.appContainer) private var container
    @State private var playlists: [LBPlaylistSummary] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if !playlists.isEmpty {
                VStack(alignment: .leading, spacing: DiapasonSpacing.s) {
                    Text("From ListenBrainz")
                        .font(.SectionTitle)
                        .padding(.horizontal, DiapasonSpacing.l)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DiapasonSpacing.m) {
                            ForEach(playlists) { pl in
                                NavigationLink {
                                    LBPlaylistDetailView(summary: pl)
                                } label: {
                                    LBPlaylistCard(summary: pl)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, DiapasonSpacing.l)
                    }
                }
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            guard let username = await container?.listenBrainzService.currentSnapshot().username else { return }
            playlists = await LBPlaylistClient.createdFor(username: username)
        }
    }
}

private struct LBPlaylistCard: View {
    let summary: LBPlaylistSummary
    var body: some View {
        VStack(alignment: .leading, spacing: DiapasonSpacing.xs) {
            RoundedRectangle(cornerRadius: DiapasonCornerRadius.large, style: .continuous)
                .fill(LinearGradient(colors: [Color.accent, Color.accent.opacity(0.55)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 150, height: 150)
                .overlay(Image(systemName: "music.note.list").font(.system(size: 40)).foregroundStyle(.white))
            Text(summary.title)
                .font(.CellTitle)
                .foregroundStyle(DiapasonColors.textPrimary)
                .lineLimit(1)
            Text("ListenBrainz")
                .font(.Caption)
                .foregroundStyle(DiapasonColors.textSecondary)
        }
        .frame(width: 150)
    }
}

struct LBPlaylistDetailView: View {
    let summary: LBPlaylistSummary
    @Environment(\.appContainer) private var container
    @State private var items: [DisplayableSong] = []
    @State private var fromYouTube = 0
    @State private var isLoading = true

    private func isYouTube(_ song: DisplayableSong) -> Bool { song.id.hasPrefix(YouTubeID.prefix) }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                EmptyStateView(systemImage: "music.note.list", title: "Empty Playlist")
            } else {
                List {
                    Section {
                        Button {
                            play(startIndex: 0)
                        } label: {
                            Label("Play \(items.count) tracks", systemImage: "play.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        if fromYouTube > 0 {
                            Text("\(fromYouTube) track\(fromYouTube == 1 ? "" : "s") streamed from YouTube (not in your library)")
                                .font(.Caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, song in
                        Button { play(startIndex: index) } label: {
                            HStack(spacing: DiapasonSpacing.m) {
                                if isYouTube(song) {
                                    RoundedRectangle(cornerRadius: DiapasonCornerRadius.standard)
                                        .fill(Color.red.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                        .overlay(Image(systemName: "play.rectangle.fill").foregroundStyle(.red))
                                } else {
                                    CoverArtCard(id: song.coverArtId ?? song.id, size: 44)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title).font(.CellTitle).foregroundStyle(DiapasonColors.textPrimary).lineLimit(1)
                                    if let a = song.artist { Text(a).font(.Caption).foregroundStyle(DiapasonColors.textSecondary).lineLimit(1) }
                                }
                                Spacer(minLength: 0)
                                if isYouTube(song) {
                                    Text("YouTube").font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(.red))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(summary.title)
        .task { await resolve() }
    }

    private func resolve() async {
        guard let library = container?.libraryService else { isLoading = false; return }
        let tracks = await LBPlaylistClient.tracks(playlistMbid: summary.id)
        var built: [DisplayableSong] = []
        var yt = 0
        for t in tracks {
            let results = (try? await library.search("\(t.artist) \(t.title)"))?.song ?? []
            if let hit = bestMatch(results, artist: t.artist, title: t.title) {
                built.append(DisplayableSong(from: hit))
            } else {
                built.append(.youtube(artist: t.artist, title: t.title))
                yt += 1
            }
        }
        items = built
        fromYouTube = yt
        isLoading = false
    }

    private func bestMatch(_ songs: [Song], artist: String, title: String) -> Song? {
        let t = title.lowercased()
        return songs.first { $0.title.lowercased() == t }
            ?? songs.first { $0.title.lowercased().contains(t) || t.contains($0.title.lowercased()) }
    }

    private func play(startIndex: Int) {
        guard let player = container?.playerService else { return }
        Task { try? await player.play(tracks: items, startIndex: startIndex) }
    }
}
