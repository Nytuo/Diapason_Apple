// Diapason — download YouTube-backed tracks for offline playback.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

@MainActor
final class YouTubeDownloadManager: ObservableObject {
    static let shared = YouTubeDownloadManager()

    struct Record: Codable {
        let songId: String
        let title: String
        let artist: String
        let coverId: String?
        let relativePath: String
    }

    @Published private(set) var records: [String: Record] = [:]
    @Published private(set) var downloading: Set<String> = []

    private let fm = FileManager.default

    private var dir: URL {
        let d = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("youtube_downloads", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var dbURL: URL { dir.appendingPathComponent("index.json") }

    private init() { load() }

    func isDownloaded(_ songId: String) -> Bool { localURL(forSongId: songId) != nil }
    func isDownloading(_ songId: String) -> Bool { downloading.contains(songId) }

    func localURL(forSongId songId: String) -> URL? {
        guard let rec = records[songId] else { return nil }
        let url = dir.appendingPathComponent(rec.relativePath)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    func downloadedSongs() -> [DisplayableSong] {
        records.values
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { rec in
                DisplayableSong(
                    id: rec.songId, title: rec.title, artist: rec.artist,
                    albumId: nil, albumName: nil, artistId: nil, genre: nil, duration: 0,
                    trackNumber: nil, isDownloaded: true, coverArtId: rec.coverId,
                    audioFormat: "YouTube", replayGainTrackGain: nil, replayGainTrackPeak: nil,
                    replayGainAlbumGain: nil, replayGainAlbumPeak: nil, replayGainBaseGain: nil, replayGainFallbackGain: nil
                )
            }
    }

    func download(_ song: DisplayableSong) {
        let songId = song.id
        guard records[songId] == nil, !downloading.contains(songId) else { return }
        downloading.insert(songId)
        Task { [weak self] in
            guard let self else { return }
            let audio = await Self.resolveStream(for: songId, artist: song.artist ?? "", title: song.title)
            defer { self.downloading.remove(songId) }
            guard let audio else { return }
            do {
                let (tmp, _) = try await URLSession.shared.download(from: audio.url)
                let filename = UUID().uuidString + ".m4a"
                let dest = self.dir.appendingPathComponent(filename)
                try? self.fm.removeItem(at: dest)
                try self.fm.moveItem(at: tmp, to: dest)
                let rec = Record(songId: songId, title: song.title, artist: song.artist ?? "",
                                 coverId: song.coverArtId, relativePath: filename)
                self.records[songId] = rec
                self.save()
            } catch {}
        }
    }

    func delete(_ songId: String) {
        if let rec = records[songId] {
            try? fm.removeItem(at: dir.appendingPathComponent(rec.relativePath))
        }
        records[songId] = nil
        save()
    }

    private nonisolated static func resolveStream(for songId: String, artist: String, title: String) async -> ResolvedAudio? {
        if let videoId = YouTubeID.decodeVideo(songId) {
            return await YouTubeResolver.shared.resolveVideo(id: videoId, title: title)
        }
        if let (a, t) = YouTubeID.decode(songId) {
            return await YouTubeResolver.shared.resolve(artist: a, title: t)
        }
        return await YouTubeResolver.shared.resolve(artist: artist, title: title)
    }

    private func load() {
        guard let data = try? Data(contentsOf: dbURL),
              let decoded = try? JSONDecoder().decode([String: Record].self, from: data) else { return }
        records = decoded
    }
    private func save() {
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: dbURL) }
    }
}
