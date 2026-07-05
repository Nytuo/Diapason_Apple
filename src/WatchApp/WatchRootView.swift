// Diapason Watch — library list + on-device player UI.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WatchRootView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @EnvironmentObject private var player: WatchAudioPlayer

    var body: some View {
        NavigationStack {
            Group {
                if store.tracks.isEmpty {
                    emptyState
                } else {
                    libraryList
                }
            }
            .navigationTitle("Diapason")
            .toolbar {
                if player.currentTrack != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            WatchPlayerView()
                        } label: {
                            Image(systemName: "waveform")
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No Downloads")
                .font(.headline)
            Text("Send downloads from the Diapason app on your iPhone: Settings ▸ Apple Watch.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var libraryList: some View {
        List {
            ForEach(store.tracks) { track in
                NavigationLink {
                    WatchPlayerView()
                        .onAppear { play(track) }
                } label: {
                    WatchTrackRow(track: track, isCurrent: player.currentTrack?.id == track.id)
                }
            }
            .onDelete { offsets in
                offsets.map { store.tracks[$0] }.forEach(store.remove)
            }
        }
    }

    private func play(_ track: WatchTrack) {
        guard player.currentTrack?.id != track.id,
              let index = store.tracks.firstIndex(of: track) else { return }
        player.play(store.tracks, startAt: index)
    }
}

private struct WatchTrackRow: View {
    @EnvironmentObject private var store: WatchLibraryStore
    let track: WatchTrack
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 8) {
            cover
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                if !track.artist.isEmpty {
                    Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        #if canImport(UIKit)
        if let url = store.coverURL(forCoverArtId: track.coverArtId), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.3))
            Image(systemName: "music.note").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct WatchPlayerView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @EnvironmentObject private var player: WatchAudioPlayer

    var body: some View {
        VStack(spacing: 8) {
            cover
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: 1) {
                Text(player.currentTrack?.title ?? "Not Playing")
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                if let artist = player.currentTrack?.artist, !artist.isEmpty {
                    Text(artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            ProgressView(value: player.duration > 0 ? min(player.position / player.duration, 1) : 0)
                .tint(Color.accentColor)

            HStack(spacing: 14) {
                button("backward.fill", 18) { player.previous() }
                button(player.isPlaying ? "pause.fill" : "play.fill", 26, prominent: true) { player.togglePlayPause() }
                button("forward.fill", 18) { player.next() }
            }
        }
        .padding(.horizontal, 6)
        .navigationTitle("Now Playing")
    }

    @ViewBuilder
    private var cover: some View {
        #if canImport(UIKit)
        if let id = player.currentTrack?.coverArtId,
           let url = store.coverURL(forCoverArtId: id),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.3))
                Image(systemName: "music.note").foregroundStyle(.secondary)
            }
        }
        #else
        RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.3))
        #endif
    }

    private func button(_ symbol: String, _ size: CGFloat, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: prominent ? 50 : 40, height: prominent ? 50 : 40)
                .background(Circle().fill(.white.opacity(prominent ? 0.28 : 0.16)))
        }
        .buttonStyle(.plain)
    }
}
