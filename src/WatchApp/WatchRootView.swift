// Diapason Watch — the watch UI.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Three things the watch is for, in the order you would want them on a run:
///
///  - **Offline** — what is actually on the watch. No phone, no signal, no server.
///  - **Library** — everything the phone told us about. Streams straight from the
///    music server, so it needs a network but *not* the phone.
///  - **Remote** — drive the phone, when the phone is around.
struct WatchRootView: View {
    var body: some View {
        TabView {
            OfflineView()
            LibraryView()
            RemoteView()
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Offline

struct OfflineView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @EnvironmentObject private var player: WatchAudioPlayer

    var body: some View {
        NavigationStack {
            List {
                if store.downloaded.isEmpty {
                    Text("Nothing downloaded yet.\n\nDownload tracks from Library and they play here with no phone and no signal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.downloaded) { track in
                        Button {
                            player.play(store.downloaded, startAt: store.downloaded.firstIndex(of: track) ?? 0)
                        } label: {
                            TrackRow(track: track)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.removeDownload(track)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }

                if player.currentTrack != nil {
                    NavigationLink("Now Playing") { NowPlayingView() }
                }
            }
            .navigationTitle("Offline")
        }
    }
}

// MARK: - Library

struct LibraryView: View {
    @EnvironmentObject private var store: WatchLibraryStore
    @EnvironmentObject private var player: WatchAudioPlayer
    @EnvironmentObject private var connect: WatchConnect

    @State private var isSyncing = false
    @State private var syncProblem: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await sync() }
                    } label: {
                        HStack {
                            Label(isSyncing ? "Syncing…" : "Sync from phone",
                                  systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isSyncing { ProgressView() }
                        }
                    }
                    .disabled(isSyncing)

                    // A sync that quietly does nothing is indistinguishable from a
                    // phone with an empty library, so say which it was.
                    if let syncProblem {
                        Text(syncProblem)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let lastSync = store.lastSync {
                        Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if store.tracks.isEmpty {
                    Text("No tracks yet. Sync from the phone to bring your library over — after that, playing and downloading go straight to your music server.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(store.tracks) { track in
                    Button {
                        player.play(store.tracks, startAt: store.tracks.firstIndex(of: track) ?? 0)
                    } label: {
                        TrackRow(track: track, isDownloading: store.downloading.contains(track.id))
                    }
                    .swipeActions {
                        if track.isDownloaded {
                            Button(role: .destructive) {
                                store.removeDownload(track)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        } else {
                            Button {
                                Task { await store.download(track) }
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
        }
    }

    /// The phone is needed for *this* and nothing else. Once the catalogue is on
    /// the watch, playing and downloading go straight to the music server.
    ///
    /// Every failure here is expected rather than exceptional — the phone is off,
    /// on another network, or simply not running Diapason — so each one leaves
    /// what is already on the watch alone and explains itself. Whatever has been
    /// downloaded keeps playing regardless; that is the point of Offline.
    private func sync() async {
        isSyncing = true
        syncProblem = nil
        defer { isSyncing = false }

        if connect.peers.isEmpty {
            connect.startDiscovery()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }

        guard let peer = connect.connectedPeer ?? connect.peers.first else {
            syncProblem = store.downloaded.isEmpty
                ? "No Diapason app found. Open Diapason on your phone, on this Wi-Fi."
                : "No Diapason app found. Downloaded tracks still play in Offline."
            return
        }

        let fetched = await connect.fetchLibrary(from: peer)
        guard !fetched.isEmpty else {
            syncProblem = "\(peer.name) sent no tracks. Its library may still be loading."
            return
        }

        store.merge(fetched)
    }
}

// MARK: - Remote

struct RemoteView: View {
    @EnvironmentObject private var connect: WatchConnect

    var body: some View {
        NavigationStack {
            if let peer = connect.connectedPeer {
                VStack(spacing: 8) {
                    Text(connect.remoteStatus?.song?.title ?? "Nothing playing")
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if let artist = connect.remoteStatus?.song?.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 16) {
                        Button { connect.sendCommand("previous") } label: {
                            Image(systemName: "backward.end.fill")
                        }
                        Button {
                            connect.sendCommand(connect.remoteStatus?.isPlaying == true ? "pause" : "play")
                        } label: {
                            Image(systemName: connect.remoteStatus?.isPlaying == true ? "pause.fill" : "play.fill")
                                .font(.title2)
                        }
                        Button { connect.sendCommand("next") } label: {
                            Image(systemName: "forward.end.fill")
                        }
                    }
                    .buttonStyle(.plain)

                    Button("Disconnect") { connect.disconnect() }
                        .font(.caption2)
                }
                .navigationTitle(peer.name)
            } else {
                List {
                    if connect.peers.isEmpty {
                        Text(connect.isScanning
                             ? "Looking for Diapason…"
                             : "No Diapason app found on this network.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(connect.peers) { peer in
                        Button(peer.name) { connect.connect(to: peer) }
                    }
                    Button("Scan") { connect.startDiscovery() }
                }
                .navigationTitle("Remote")
                .task { connect.startDiscovery() }
            }
        }
    }
}

// MARK: - Shared

struct NowPlayingView: View {
    @EnvironmentObject private var player: WatchAudioPlayer

    var body: some View {
        VStack(spacing: 6) {
            Text(player.currentTrack?.title ?? "—")
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(player.currentTrack?.artist ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Offline and streaming feel identical right up until one of them
            // fails, so say which this is.
            Label(player.isOffline ? "On watch" : "Streaming",
                  systemImage: player.isOffline
                    ? "arrow.down.circle.fill"
                    : "antenna.radiowaves.left.and.right")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if player.isBuffering {
                ProgressView().scaleEffect(0.6)
            }

            HStack(spacing: 16) {
                Button { player.previous() } label: { Image(systemName: "backward.end.fill") }
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                }
                Button { player.next() } label: { Image(systemName: "forward.end.fill") }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Now Playing")
    }
}

struct TrackRow: View {
    let track: WatchTrack
    var isDownloading = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.body).lineLimit(1)
                Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)

            if isDownloading {
                ProgressView().scaleEffect(0.5)
            } else if track.isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
