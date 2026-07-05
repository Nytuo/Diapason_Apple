// Diapason Watch — on-device offline library (files synced from the iPhone).
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation

@MainActor
final class WatchLibraryStore: ObservableObject {
    @Published private(set) var tracks: [WatchTrack] = []

    private let musicDir: URL
    private let coverDir: URL
    private let manifestURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        musicDir = docs.appendingPathComponent("watch-music", isDirectory: true)
        coverDir = docs.appendingPathComponent("watch-covers", isDirectory: true)
        manifestURL = docs.appendingPathComponent("watch-manifest.json")
        try? FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: coverDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Receiving files from the phone

    /// Copies a track file delivered over WatchConnectivity into the music dir and
    /// records it in the manifest. `tempURL` is only valid for the duration of the
    /// delegate call, so the copy is synchronous.
    func ingestTrack(from tempURL: URL, metadata: [String: Any]) {
        guard let songId = metadata["songId"] as? String, !songId.isEmpty else { return }
        let suffix = (metadata["suffix"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "m4a"
        let filename = "\(sanitize(songId)).\(suffix)"
        let dest = musicDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: tempURL, to: dest)
        } catch {
            return
        }
        let duration = (metadata["duration"] as? NSNumber)?.intValue ?? 0
        let track = WatchTrack(
            id: songId,
            title: metadata["title"] as? String ?? "Unknown",
            artist: metadata["artist"] as? String ?? "",
            album: metadata["album"] as? String ?? "",
            coverArtId: metadata["coverArtId"] as? String ?? "",
            filename: filename,
            duration: duration
        )
        tracks.removeAll { $0.id == songId }
        tracks.append(track)
        tracks.sort { ($0.artist, $0.album, $0.title) < ($1.artist, $1.album, $1.title) }
        save()
    }

    func ingestCover(from tempURL: URL, metadata: [String: Any]) {
        guard let coverArtId = metadata["coverArtId"] as? String, !coverArtId.isEmpty else { return }
        let dest = coverDir.appendingPathComponent("\(sanitize(coverArtId)).jpg")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: tempURL, to: dest)
        objectWillChange.send()
    }

    // MARK: - Access

    func fileURL(for track: WatchTrack) -> URL {
        musicDir.appendingPathComponent(track.filename)
    }

    func coverURL(forCoverArtId id: String) -> URL? {
        guard !id.isEmpty else { return nil }
        let url = coverDir.appendingPathComponent("\(sanitize(id)).jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func remove(_ track: WatchTrack) {
        try? FileManager.default.removeItem(at: fileURL(for: track))
        tracks.removeAll { $0.id == track.id }
        save()
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
              let decoded = try? JSONDecoder().decode([WatchTrack].self, from: data) else { return }
        // Drop entries whose audio file went missing.
        tracks = decoded.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
    }
}
