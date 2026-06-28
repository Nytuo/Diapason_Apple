import Foundation
import SwiftUI

struct OfflineSongRecord: Codable, Identifiable {
    var id: String { song.id }
    let song: Song
    let fileName: String
    let downloadedAt: Date
    let fileSize: Int64
}

struct DownloadedPlaylistRecord: Codable, Identifiable {
    let id: String
    let name: String
    let coverArtId: String?
    let songIds: [String]
}

@MainActor
class OfflineDownloadManager: ObservableObject {
    static let shared = OfflineDownloadManager()

    @Published var downloadedSongs: [Song] = []
    @Published var downloadingSongIds: Set<String> = []
    @Published var downloadedPlaylists: [DownloadedPlaylistRecord] = []

    private let fileManager = FileManager.default
    // Records are only ever accessed on the main actor
    private var records: [OfflineSongRecord] = []
    private var playlistRecords: [DownloadedPlaylistRecord] = []

    private var offlineDir: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("offline_music", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexURL: URL { offlineDir.appendingPathComponent("downloads_index.json") }
    private var playlistsIndexURL: URL { offlineDir.appendingPathComponent("playlists_index.json") }

    private init() {
        loadIndex()
        loadPlaylistsIndex()
        syncPublishedState()
    }

    // MARK: - Persistence (called on main actor, file I/O is cheap for small indexes)

    private func loadIndex() {
        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL) else { return }
        records = (try? JSONDecoder().decode([OfflineSongRecord].self, from: data)) ?? []
    }

    private func loadPlaylistsIndex() {
        guard fileManager.fileExists(atPath: playlistsIndexURL.path),
              let data = try? Data(contentsOf: playlistsIndexURL) else { return }
        playlistRecords = (try? JSONDecoder().decode([DownloadedPlaylistRecord].self, from: data)) ?? []
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: indexURL)
        }
    }

    private func savePlaylistsIndex() {
        if let data = try? JSONEncoder().encode(playlistRecords) {
            try? data.write(to: playlistsIndexURL)
        }
    }

    /// Push current record arrays into the @Published properties (already on main actor).
    private func syncPublishedState() {
        downloadedSongs = records.map { $0.song }
        downloadedPlaylists = playlistRecords
    }

    // MARK: - Queries

    func getDownloadedURL(forSongId songId: String) -> URL? {
        guard let record = records.first(where: { $0.id == songId }) else { return nil }
        let fileURL = offlineDir.appendingPathComponent(record.fileName)

        let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
        let actualSize = (attrs?[.size] as? Int64) ?? 0

        guard actualSize > 0 else {
            // Self-heal: remove invalid record
            records.removeAll(where: { $0.id == songId })
            try? fileManager.removeItem(at: fileURL)
            saveIndex()
            syncPublishedState()
            return nil
        }
        return fileURL
    }

    func isDownloaded(songId: String) -> Bool {
        records.contains(where: { $0.id == songId })
    }

    func isDownloading(songId: String) -> Bool {
        downloadingSongIds.contains(songId)
    }

    func getDownloadedCoverArtURL(forAlbumId albumId: String) -> URL? {
        let fileURL = offlineDir.appendingPathComponent("\(albumId).jpg")
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    // MARK: - Download

    func downloadSong(song: Song, remoteURL: URL) {
        guard !records.contains(where: { $0.id == song.id }),
              !downloadingSongIds.contains(song.id) else { return }

        downloadingSongIds.insert(song.id)

        // Capture values we need inside the Task before leaving the main actor
        let offlineDirSnapshot = offlineDir
        let indexURLSnapshot = indexURL
        let songId = song.id

        Task {
            do {
                // Download first so we can determine actual audio format from Content-Type
                let (tempLocalURL, response) = try await URLSession.shared.download(from: remoteURL)

                let mimeType = (response as? HTTPURLResponse)?.mimeType ?? ""
                let fileExtension = Self.audioExtension(forMimeType: mimeType)
                    ?? (remoteURL.pathExtension.lowercased().isEmpty ? "mp3" : remoteURL.pathExtension.lowercased())
                let fileName = "\(songId).\(fileExtension)"
                let targetURL = offlineDirSnapshot.appendingPathComponent(fileName)

                // Move file (fast, on whatever thread URLSession used)
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    try? FileManager.default.removeItem(at: targetURL)
                }
                try FileManager.default.moveItem(at: tempLocalURL, to: targetURL)

                let size = (try? FileManager.default.attributesOfItem(atPath: targetURL.path)[.size] as? Int64) ?? 0

                // Cover art download (optional)
                if let coverArtURL = BackendManager.shared.client.getCoverArtURL(id: song.albumId) {
                    let coverFilename = "\(song.albumId).jpg"
                    let coverTargetURL = offlineDirSnapshot.appendingPathComponent(coverFilename)
                    if !FileManager.default.fileExists(atPath: coverTargetURL.path),
                       let (tempCoverURL, _) = try? await URLSession.shared.download(from: coverArtURL) {
                        try? FileManager.default.moveItem(at: tempCoverURL, to: coverTargetURL)
                    }
                }

                // All state mutations back on MainActor
                await MainActor.run {
                    self.records.removeAll(where: { $0.id == songId })
                    self.records.append(OfflineSongRecord(
                        song: song,
                        fileName: fileName,
                        downloadedAt: Date(),
                        fileSize: size
                    ))
                    self.downloadingSongIds.remove(songId)
                    self.saveIndex()
                    self.syncPublishedState()
                }
            } catch {
                print("Failed to download song \(song.title): \(error)")
                await MainActor.run {
                    self.downloadingSongIds.remove(songId)
                }
            }
        }
    }

    func deleteDownload(songId: String) {
        guard let record = records.first(where: { $0.id == songId }) else { return }
        let fileURL = offlineDir.appendingPathComponent(record.fileName)
        try? fileManager.removeItem(at: fileURL)
        records.removeAll(where: { $0.id == songId })

        // Update playlists that contain this song
        playlistRecords = playlistRecords.compactMap { plist in
            guard plist.songIds.contains(songId) else { return plist }
            let newIds = plist.songIds.filter { $0 != songId }
            if newIds.isEmpty { return nil }
            return DownloadedPlaylistRecord(
                id: plist.id,
                name: plist.name,
                coverArtId: plist.coverArtId,
                songIds: newIds
            )
        }

        saveIndex()
        savePlaylistsIndex()
        syncPublishedState()
    }

    // MARK: - Playlist Downloads

    func downloadPlaylist(playlist: Playlist, songs: [Song]) {
        for song in songs {
            if let remoteURL = BackendManager.shared.client.getStreamURL(id: song.id) {
                downloadSong(song: song, remoteURL: remoteURL)
            }
        }

        playlistRecords.removeAll(where: { $0.id == playlist.id })
        playlistRecords.append(DownloadedPlaylistRecord(
            id: playlist.id,
            name: playlist.name,
            coverArtId: playlist.coverArt,
            songIds: songs.map { $0.id }
        ))
        savePlaylistsIndex()
        syncPublishedState()
    }

    func downloadSongInPlaylist(playlist: Playlist, song: Song) {
        if let remoteURL = BackendManager.shared.client.getStreamURL(id: song.id) {
            downloadSong(song: song, remoteURL: remoteURL)
        }

        let existing = playlistRecords.first(where: { $0.id == playlist.id })
        var songIds = existing?.songIds ?? []
        if !songIds.contains(song.id) { songIds.append(song.id) }

        playlistRecords.removeAll(where: { $0.id == playlist.id })
        playlistRecords.append(DownloadedPlaylistRecord(
            id: playlist.id,
            name: playlist.name,
            coverArtId: playlist.coverArt ?? existing?.coverArtId,
            songIds: songIds
        ))
        savePlaylistsIndex()
        syncPublishedState()
    }

    func deleteDownloadedPlaylist(id: String) {
        playlistRecords.removeAll(where: { $0.id == id })
        savePlaylistsIndex()
        syncPublishedState()
    }

    // MARK: - Helpers

    private static func audioExtension(forMimeType mime: String) -> String? {
        switch mime.lowercased().components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) {
        case "audio/mpeg", "audio/mp3":       return "mp3"
        case "audio/flac", "audio/x-flac":    return "flac"
        case "audio/aac":                      return "aac"
        case "audio/mp4", "audio/x-m4a", "audio/m4a": return "m4a"
        case "audio/ogg":                      return "ogg"
        case "audio/opus":                     return "opus"
        case "audio/wav", "audio/x-wav":       return "wav"
        case "audio/aiff", "audio/x-aiff":    return "aiff"
        default:                               return nil
        }
    }
}
