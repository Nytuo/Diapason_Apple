// Diapason — general "Search YouTube" surface: play any track by name, and download
// for offline playback.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct SearchYouTubeView: View {
    @Environment(\.appContainer) private var container
    @ObservedObject private var downloads = YouTubeDownloadManager.shared
    @State private var query = ""
    @State private var results: [YouTubeResult] = []
    @State private var isSearching = false
    @State private var searchedOnce = false

    private func song(_ r: YouTubeResult) -> DisplayableSong {
        .youtubeVideo(videoId: r.videoId, rawTitle: r.title, channel: r.author)
    }

    var body: some View {
        Group {
            if isSearching {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                EmptyStateView(
                    systemImage: "play.rectangle.on.rectangle",
                    title: searchedOnce ? "No Results" : "Search YouTube",
                    subtitle: searchedOnce ? "Try a different search." : "Play any song by name, streamed from YouTube."
                )
            } else {
                List {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, r in
                        let s = song(r)
                        HStack(spacing: DiapasonSpacing.m) {
                            Button { play(at: index) } label: {
                                HStack(spacing: DiapasonSpacing.m) {
                                    RoundedRectangle(cornerRadius: DiapasonCornerRadius.standard)
                                        .fill(Color.red.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                        .overlay(Image(systemName: "play.rectangle.fill").foregroundStyle(.red))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.title).font(.CellTitle).foregroundStyle(DiapasonColors.textPrimary).lineLimit(2)
                                        if !r.author.isEmpty {
                                            Text(r.author).font(.Caption).foregroundStyle(DiapasonColors.textSecondary).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            downloadButton(for: s)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Search YouTube")
        .searchable(text: $query, prompt: "Songs on YouTube")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .background(DiapasonColors.backgroundPrimary.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { YouTubeDownloadsView() } label: {
                    Image(systemName: "arrow.down.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func downloadButton(for s: DisplayableSong) -> some View {
        if downloads.isDownloaded(s.id) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accent)
        } else if downloads.isDownloading(s.id) {
            ProgressView()
        } else {
            Button { downloads.download(s) } label: {
                Image(systemName: "arrow.down.circle").foregroundStyle(DiapasonColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        searchedOnce = true
        results = await YouTubeResolver.shared.search(q)
        isSearching = false
    }

    private func play(at index: Int) {
        guard let player = container?.playerService else { return }
        let tracks = results.map { song($0) }
        Task { try? await player.play(tracks: tracks, startIndex: index) }
    }
}

struct YouTubeDownloadsView: View {
    @Environment(\.appContainer) private var container
    @ObservedObject private var downloads = YouTubeDownloadManager.shared

    private var songs: [DisplayableSong] { downloads.downloadedSongs() }

    var body: some View {
        Group {
            if songs.isEmpty {
                EmptyStateView(systemImage: "arrow.down.circle", title: "No YouTube Downloads",
                               subtitle: "Download tracks from Search YouTube to play them offline.")
            } else {
                List {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, s in
                        Button { play(songs, at: index) } label: {
                            HStack(spacing: DiapasonSpacing.m) {
                                CoverArtCard(id: s.coverArtId ?? s.id, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title).font(.CellTitle).foregroundStyle(DiapasonColors.textPrimary).lineLimit(1)
                                    if let a = s.artist { Text(a).font(.Caption).foregroundStyle(DiapasonColors.textSecondary).lineLimit(1) }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        #if !os(tvOS)
                        .swipeActions {
                            Button(role: .destructive) { downloads.delete(s.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        #endif
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("YouTube Downloads")
        .background(DiapasonColors.backgroundPrimary.ignoresSafeArea())
    }

    private func play(_ list: [DisplayableSong], at index: Int) {
        guard let player = container?.playerService else { return }
        Task { try? await player.play(tracks: list, startIndex: index) }
    }
}
