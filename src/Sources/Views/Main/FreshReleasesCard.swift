// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Horizontal scroll card showing personalized fresh releases from ListenBrainz.
/// Shows an empty state when releases are unavailable instead of collapsing.
struct FreshReleasesCard: View {
    let releases: [AlbumRecommendation]
    let isLoading: Bool
    let isListenBrainzConnected: Bool
    let onSeeAll: () -> Void
    /// macOS only — tapped release to present in a sheet.
    var onTap: ((AlbumRecommendation) -> Void)? = nil
    /// iOS only — namespace for zoom matched-transition source on each cell.
    var zoomNamespace: Namespace.ID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DiapasonSpacing.s) {
            HStack {
                Text("Fresh Releases")
                    .font(.SectionTitle)
                Spacer(minLength: 0)
                if !releases.isEmpty {
                    Button(action: onSeeAll) {
                        Text("See all")
                            .font(.Caption)
                            .foregroundStyle(Color.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DiapasonSpacing.m)

            if isLoading {
                skeletonScroll
            } else if !releases.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: DiapasonSpacing.s) {
                        ForEach(Array(releases.enumerated()), id: \.offset) { _, release in
                            #if os(iOS)
                            FreshReleaseAlbumCell(
                                release: release,
                                zoomSourceId: release.id ?? "\(release.artistName)-\(release.title)",
                                zoomNamespace: zoomNamespace
                            )
                            .frame(width: 140)
                            #else
                            FreshReleaseAlbumCell(release: release, onTap: { onTap?(release) })
                                .frame(width: 140)
                            #endif
                        }
                        seeAllCell
                    }
                    .padding(.horizontal, DiapasonSpacing.m)
                }
            } else if !isListenBrainzConnected {
                emptyStatePlaceholder(
                    icon: "waveform.circle",
                    message: "Connect ListenBrainz in Settings to discover fresh releases based on your listening history."
                )
            } else {
                emptyStatePlaceholder(
                    icon: "music.note.list",
                    message: "No fresh releases found based on your recent listening history."
                )
            }
        }
    }

    private func emptyStatePlaceholder(icon: String, message: String) -> some View {
        VStack(spacing: DiapasonSpacing.s) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.Caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 168)
        .padding(.horizontal, DiapasonSpacing.m)
    }

    private var seeAllCell: some View {
        Button(action: onSeeAll) {
            VStack(alignment: .leading, spacing: DiapasonSpacing.xs) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: DiapasonCornerRadius.standard, style: .continuous)
                                .fill(Color.accentColor.opacity(0.08))
                            VStack(spacing: DiapasonSpacing.xs) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(Color.accent)
                                Text("See all")
                                    .font(.CellTitle)
                                    .foregroundStyle(Color.accent)
                            }
                        }
                    }
                Text("Past 90 days")
                    .font(.Caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 140)
        }
        .buttonStyle(.plain)
    }

    private var skeletonScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: DiapasonSpacing.s) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: DiapasonSpacing.xs) {
                        SkeletonBlock(width: 140, height: 140, cornerRadius: DiapasonCornerRadius.standard)
                        SkeletonBlock(width: 110, height: 12)
                        SkeletonBlock(width: 80, height: 10)
                    }
                    .frame(width: 140)
                }
            }
            .padding(.horizontal, DiapasonSpacing.m)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Cell

struct FreshReleaseAlbumCell: View {
    let release: AlbumRecommendation
    /// macOS only — called when the cell is tapped.
    var onTap: (() -> Void)? = nil
    /// iOS only — zoom matched-transition source ID.
    var zoomSourceId: String? = nil
    /// iOS only — zoom matched-transition namespace.
    var zoomNamespace: Namespace.ID? = nil

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        #if os(iOS)
        NavigationLink(value: release) {
            cellContent
        }
        .buttonStyle(.plain)
        .diapasonMatchedTransitionSource(id: zoomSourceId, in: zoomNamespace)
        #else
        Button(action: { onTap?() }) {
            cellContent
        }
        .buttonStyle(.plain)
        #endif
    }

    private var cellContent: some View {
        VStack(alignment: .leading, spacing: DiapasonSpacing.xs) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ExternalCoverView(url: release.coverArtURL) {
                        Color.secondary.opacity(0.2)
                    }
                }
                .diapasonCoverStyle()

            Text(release.title)
                .font(.CellTitle)
                .lineLimit(1)

            Text(release.artistName)
                .font(.Caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let date = release.releaseDate {
                Text(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))
                    .font(.Caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
