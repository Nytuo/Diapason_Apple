// Diapason — flat "Songs" list on the Home tab. Works across all backends via the
// library router.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
import SwiftSonic

struct AllSongsView: View {
    @Environment(\.appContainer) private var container
    @State private var songs: [Song] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if songs.isEmpty {
                EmptyStateView(systemImage: "music.note", title: "No Songs")
            } else {
                List {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        Button {
                            play(at: index)
                        } label: {
                            HStack(spacing: DiapasonSpacing.m) {
                                CoverArtCard(id: song.coverArt ?? song.albumId ?? song.id, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.CellTitle)
                                        .foregroundStyle(DiapasonColors.textPrimary)
                                        .lineLimit(1)
                                    if let artist = song.artist {
                                        Text(artist)
                                            .font(.Caption)
                                            .foregroundStyle(DiapasonColors.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(DiapasonColors.backgroundPrimary)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Songs")
        .background(DiapasonColors.backgroundPrimary.ignoresSafeArea())
        .task { await load() }
    }

    private func load() async {
        guard let library = container?.libraryService else { isLoading = false; return }
        let fetched = (try? await library.randomSongs(size: 1000)) ?? []
        songs = fetched.sorted {
            ($0.artist ?? "", $0.album ?? "", $0.track ?? 0, $0.title)
                < ($1.artist ?? "", $1.album ?? "", $1.track ?? 0, $1.title)
        }
        isLoading = false
    }

    private func play(at index: Int) {
        guard let player = container?.playerService else { return }
        let tracks = songs.map { DisplayableSong(from: $0) }
        Task { try? await player.play(tracks: tracks, startIndex: index) }
    }
}
