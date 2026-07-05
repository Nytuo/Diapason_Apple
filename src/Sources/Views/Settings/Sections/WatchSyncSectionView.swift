// Diapason — Settings section to sync downloads to the Apple Watch.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

#if os(iOS)
import SwiftUI

struct WatchSyncSectionView: View {
    @EnvironmentObject private var watch: WatchConnectivityService
    @State private var count = 0

    var body: some View {
        Section {
            NavigationLink {
                WatchSyncPickerView()
            } label: {
                Label {
                    Text("Sync Music to Apple Watch")
                } icon: {
                    SettingsIcon(systemImage: "applewatch", color: Color.cassetteAccent)
                }
            }
            .disabled(count == 0)

            Text(count == 0
                 ? "Download albums or playlists first to sync them for offline playback on your watch."
                 : "\(count) downloaded track\(count == 1 ? "" : "s") available for offline, on-device watch playback.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Apple Watch")
        }
        .onAppear { count = watch.downloadedTrackCount() }
    }
}

/// Pick which downloaded playlists (or everything) to transfer to the watch.
struct WatchSyncPickerView: View {
    @EnvironmentObject private var watch: WatchConnectivityService
    @State private var playlists: [WatchSyncablePlaylist] = []
    @State private var selected: Set<String> = []

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Watch", systemImage: "applewatch")
                    Spacer()
                    Text(watch.sessionSummary())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await watch.syncDownloadsToWatch() }
                } label: {
                    Label("Sync All Downloads", systemImage: "arrow.down.circle.fill")
                }
                .disabled(watch.isSyncing)
            } footer: {
                if !watch.status.isEmpty {
                    Text(watch.status)
                }
            }

            if !playlists.isEmpty {
                Section("Playlists") {
                    ForEach(playlists) { playlist in
                        Button {
                            toggle(playlist.id)
                        } label: {
                            HStack {
                                CoverArtView(id: playlist.coverArtId ?? playlist.id, size: 80, cornerRadius: 6,
                                             placeholderSystemImage: "music.note.list")
                                    .frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name).lineLimit(1)
                                    Text("\(playlist.trackCount) tracks")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(playlist.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(playlist.id) ? Color.cassetteAccent : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button {
                        Task { await watch.syncPlaylists(Array(selected)) }
                    } label: {
                        HStack {
                            Label(watch.isSyncing ? "Syncing… \(watch.syncedCount)/\(watch.totalToSync)" : "Sync Selected Playlists",
                                  systemImage: "applewatch.radiowaves.left.and.right")
                            Spacer()
                            if watch.isSyncing { ProgressView() }
                        }
                    }
                    .disabled(watch.isSyncing || selected.isEmpty)
                }
            }
        }
        .navigationTitle("Sync to Watch")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { playlists = watch.downloadedPlaylists() }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}
#endif
