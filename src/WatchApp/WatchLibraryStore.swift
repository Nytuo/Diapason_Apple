// Diapason Watch — the watch's catalogue and its offline downloads.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation
import os

private let storeLog = Logger(subsystem: "fr.nytuo.diapason.watch", category: "Library")

/// What the watch knows about, and what it actually has on it.
///
/// Two different things, deliberately kept apart:
///
///  - the **catalogue** is synced from the phone and is only metadata plus a
///    stream URL. It outlives the phone leaving, so the watch can still browse
///    and stream on its own.
///  - a **download** is the audio file itself, on the watch. That is what plays
///    with no network at all.
@MainActor
final class WatchLibraryStore: ObservableObject {
    /// Everything the watch knows about, downloaded or not.
    @Published private(set) var tracks: [WatchTrack] = []

    /// Tracks being downloaded right now, so the UI can say so.
    @Published private(set) var downloading: Set<String> = []

    @Published private(set) var lastSync: Date?

    var downloaded: [WatchTrack] { tracks.filter(\.isDownloaded) }

    private let musicDir: URL
    private let manifestURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        musicDir = docs.appendingPathComponent("watch-music", isDirectory: true)
        manifestURL = docs.appendingPathComponent("watch-manifest.json")
        try? FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Catalogue

    /// Merges a freshly-fetched catalogue in.
    ///
    /// Downloads survive a sync: a track already on the watch keeps its file, and
    /// only its metadata and stream URL are refreshed — the URL genuinely can
    /// change, since a server may reissue its token.
    ///
    /// A downloaded track that has vanished from the phone's library is kept. The
    /// user took it offline deliberately, and deleting their music because a
    /// server went away would be a nasty surprise.
    func merge(_ fetched: [WatchTrack]) {
        let existing = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var merged: [String: WatchTrack] = [:]

        for var track in fetched {
            track.filename = existing[track.id]?.filename
            merged[track.id] = track
        }
        for track in tracks where track.isDownloaded && merged[track.id] == nil {
            merged[track.id] = track
        }

        tracks = merged.values.sorted { ($0.artist, $0.album, $0.title) < ($1.artist, $1.album, $1.title) }
        lastSync = Date()
        save()

        storeLog.notice("Catalogue holds \(self.tracks.count) track(s), \(self.downloaded.count) downloaded")
    }

    // MARK: - Downloads

    func fileURL(for track: WatchTrack) -> URL? {
        guard let filename = track.filename else { return nil }
        return musicDir.appendingPathComponent(filename)
    }

    /// Pulls the audio down from the music server, so it plays with no network at
    /// all. The URL goes straight to the server, so the phone need not be around.
    func download(_ track: WatchTrack) async {
        guard !track.isDownloaded, !downloading.contains(track.id) else { return }
        guard let url = URL(string: track.streamUrl) else { return }

        downloading.insert(track.id)
        defer { downloading.remove(track.id) }

        do {
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                storeLog.error("Download of \(track.title) returned a bad status")
                return
            }

            // Keep the server's extension where there is one: the player sniffs
            // the container from it.
            let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
            let filename = "\(sanitize(track.id)).\(ext)"
            let destination = musicDir.appendingPathComponent(filename)

            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)

            if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                tracks[index].filename = filename
                save()
            }
            storeLog.notice("Downloaded \(track.title)")
        } catch {
            storeLog.error("Download of \(track.title) failed: \(error.localizedDescription)")
        }
    }

    /// Deletes the audio but keeps the catalogue entry, so the track can still be
    /// streamed — or downloaded again later.
    func removeDownload(_ track: WatchTrack) {
        if let url = fileURL(for: track) {
            try? FileManager.default.removeItem(at: url)
        }
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[index].filename = nil
            save()
        }
    }

    // MARK: - Persistence

    private func sanitize(_ s: String) -> String {
        String(s.map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              var decoded = try? JSONDecoder().decode([WatchTrack].self, from: data)
        else { return }

        // A manifest entry whose file has gone missing is still a perfectly good
        // catalogue entry — it simply is not downloaded any more.
        for index in decoded.indices {
            if let filename = decoded[index].filename {
                let url = musicDir.appendingPathComponent(filename)
                if !FileManager.default.fileExists(atPath: url.path) {
                    decoded[index].filename = nil
                }
            }
        }
        tracks = decoded
    }
}
