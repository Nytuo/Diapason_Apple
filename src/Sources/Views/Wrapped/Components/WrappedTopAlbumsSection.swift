// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct WrappedTopAlbumsSection: View {
    let albums: [TopAlbumEntry]

    
    private let columns = [
        GridItem(.flexible(), spacing: DiapasonSpacing.m),
        GridItem(.flexible(), spacing: DiapasonSpacing.m)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DiapasonSpacing.s) {
            Text("Top Albums")
                .font(.SectionTitle)
            if albums.isEmpty {
                emptyLabel("No album data for this period.")
            } else {
                LazyVGrid(columns: columns, spacing: DiapasonSpacing.m) {
                    ForEach(albums.prefix(6)) { album in
                        NavigationLink {
                            #if os(macOS)
                            AlbumDetailMacOS(albumId: album.albumId, albumName: album.title, coverArtId: album.albumId)
                            #else
                            AlbumDetailView(albumId: album.albumId, albumName: album.title, coverArtId: album.albumId)
                            #endif
                        } label: {
                            albumCard(album)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func albumCard(_ album: TopAlbumEntry) -> some View {
        VStack(alignment: .leading, spacing: DiapasonSpacing.xs) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        CoverArtView(id: album.albumId, size: 220, tier: .hero)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DiapasonCornerRadius.standard, style: .continuous))
                    .diapasonCoverStyle(cornerRadius: DiapasonCornerRadius.standard)
                rankBadge(album.rank)
                    .padding(DiapasonSpacing.xs)
            }
            Text(album.title)
                .font(.CellTitle)
                .lineLimit(1)
            Text(album.artistName)
                .font(.Caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func medalColor(for rank: Int) -> Color {
        switch rank {
        case 1: return WrappedYearPalette.medalGold
        case 2: return WrappedYearPalette.medalSilver
        case 3: return WrappedYearPalette.medalBronze
        default: return DiapasonColors.accent
        }
    }

    private func rankBadge(_ rank: Int) -> some View {
        let isMedal = rank <= 3
        return Text("#\(rank)")
            .font(.Caption2)
            .fontWeight(.bold)
            .foregroundStyle(isMedal ? Color.black : Color.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                if isMedal {
                    Capsule().fill(medalColor(for: rank))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.Caption)
            .foregroundStyle(.secondary)
    }
}
