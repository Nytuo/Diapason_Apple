// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedYearlyListView: View {
    @Environment(\.appContainer) private var container
    @State private var playlists: [WrappedYearlyPlaylist] = []
    @State private var isLoading = true

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var hasCurrentYearPlaylist: Bool {
        playlists.contains { $0.year == currentYear }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DiapasonSpacing.l) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, DiapasonSpacing.xxxxl)
                } else if playlists.isEmpty && hasCurrentYearPlaylist {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: DiapasonSpacing.s)],
                        spacing: DiapasonSpacing.s
                    ) {
                        if !hasCurrentYearPlaylist {
                            WrappedRecapMonthCard(period: .year(currentYear))
                        }
                        ForEach(playlists) { playlist in
                            WrappedYearlyCard(playlist: playlist)
                        }
                    }

                    NavigationLink {
                        WrappedView()
                    } label: {
                        HStack(spacing: DiapasonSpacing.s) {
                            Image(systemName: "chart.bar.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("View Listening Stats")
                                    .font(.CellTitle)
                                    .foregroundStyle(.primary)
                                Text("Monthly and annual breakdowns")
                                    .font(.Caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(DiapasonSpacing.m)
                        .background(Color.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: DiapasonCornerRadius.standard, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DiapasonSpacing.l)
        }
        .diapasonContentWidth()
        .navigationTitle("Wrapped")
        .task {
            guard let container,
                  let serverId = container.serverState.activeServer?.id.uuidString else {
                isLoading = false
                return
            }
            playlists = await container.wrappedPlaylistService.fetchYearlyPlaylists(serverId: serverId)
            isLoading = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: DiapasonSpacing.s) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(Color.accent.opacity(0.5))
            Text("No Wrapped playlists yet.")
                .font(.CellTitle)
            Text("Your Wrapped \(currentYear) will be available on December 28.")
                .font(.Caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DiapasonSpacing.xxxxl)
    }
}
