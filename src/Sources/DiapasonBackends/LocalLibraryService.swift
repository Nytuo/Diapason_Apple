// Diapason — Local-files backend adapter for the Cassette UI.
// Implements Cassette's LibraryServiceProtocol against on-device audio files,
// producing SwiftSonic model types so the forked Cassette views work unchanged.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.
// Consumes Cassette (MPL-2.0) protocols; see LICENSE-Cassette / NOTICE-Cassette.

import Foundation
import AVFoundation
import SwiftSonic
import UIKit

private struct LocalTrackRecord: Codable {
    var song: Song
    var relativePath: String
    var coverPath: String?
    var starred: Bool
}

actor LocalLibraryService: LibraryServiceProtocol {

    private var records: [LocalTrackRecord] = []
    private var loaded = false

    private nonisolated var baseDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("local_music", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private nonisolated var filesDir: URL {
        let dir = baseDir.appendingPathComponent("files", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private nonisolated var coversDir: URL {
        let dir = baseDir.appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private nonisolated var dbURL: URL { baseDir.appendingPathComponent("diapason-local.json") }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: dbURL),
              let decoded = try? JSONDecoder().decode([LocalTrackRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: dbURL) }
    }

    func importFile(from url: URL, filename: String) async -> Song? {
        loadIfNeeded()
        let songId = "local_song_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let ext = (URL(fileURLWithPath: filename).pathExtension.isEmpty ? url.pathExtension : URL(fileURLWithPath: filename).pathExtension)
        let suffix = ext.isEmpty ? "mp3" : ext.lowercased()
        let relative = "\(songId).\(suffix)"
        let target = filesDir.appendingPathComponent(relative)
        try? FileManager.default.removeItem(at: target)
        do { try FileManager.default.copyItem(at: url, to: target) }
        catch { return nil }

        let (title, artist, album, track, year, duration, artwork) = await Self.readMetadata(target, fallbackTitle: filename)
        let artistId = "local_art_" + Self.slug(artist)
        let albumId = "local_alb_" + Self.slug(artist + "_" + album)

        var coverPath: String?
        if let artwork {
            let coverURL = coversDir.appendingPathComponent("\(albumId).jpg")
            try? artwork.write(to: coverURL)
            coverPath = coverURL.path
        }

        let song = Song(
            id: songId, title: title, album: album, artist: artist,
            track: track, year: year, coverArt: albumId, suffix: suffix,
            duration: duration, albumId: albumId, artistId: artistId
        )
        records.append(LocalTrackRecord(song: song, relativePath: relative, coverPath: coverPath, starred: false))
        save()
        return song
    }

    private static func readMetadata(_ url: URL, fallbackTitle: String) async -> (String, String, String, Int?, Int?, Int, Data?) {
        let asset = AVURLAsset(url: url)
        var title = fallbackTitle, artist = "Unknown Artist", album = "Unknown Album"
        var track: Int?, year: Int?, duration = 0
        var artwork: Data?
        if let d = try? await asset.load(.duration).seconds, !d.isNaN { duration = Int(d) }
        if let meta = try? await asset.load(.commonMetadata) {
            for item in meta {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle: title = (try? await item.load(.stringValue)) ?? title
                case .commonKeyArtist: artist = (try? await item.load(.stringValue)) ?? artist
                case .commonKeyAlbumName: album = (try? await item.load(.stringValue)) ?? album
                case .commonKeyArtwork: artwork = try? await item.load(.dataValue)
                default: break
                }
            }
        }
        return (title.trimmed, artist.trimmed, album.trimmed, track, year, duration, artwork)
    }

    private static func slug(_ s: String) -> String {
        s.components(separatedBy: CharacterSet.alphanumerics.inverted).joined().lowercased()
    }

    private func albumsIndex() -> [AlbumID3] {
        loadIfNeeded()
        let groups = Dictionary(grouping: records, by: { $0.song.albumId ?? "" })
        return groups.compactMap { (albumId, recs) -> AlbumID3? in
            guard let first = recs.first?.song, !albumId.isEmpty else { return nil }
            let totalDuration = recs.reduce(0) { $0 + ($1.song.duration ?? 0) }
            return AlbumID3(
                id: albumId, name: first.album ?? "Unknown Album",
                songCount: recs.count, duration: totalDuration,
                artist: first.artist, artistId: first.artistId, coverArt: albumId, year: first.year,
                song: recs.map(\.song).sorted { ($0.track ?? 0) < ($1.track ?? 0) }
            )
        }
        .sorted { ($0.name).localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func artistsIndex() -> [ArtistID3] {
        loadIfNeeded()
        let byArtist = Dictionary(grouping: records, by: { $0.song.artistId ?? "" })
        return byArtist.compactMap { (artistId, recs) -> ArtistID3? in
            guard let first = recs.first?.song, !artistId.isEmpty else { return nil }
            let albumCount = Set(recs.compactMap { $0.song.albumId }).count
            return ArtistID3(id: artistId, name: first.artist ?? "Unknown Artist", albumCount: albumCount, coverArt: recs.first?.song.albumId)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func artists() async throws -> [ArtistIndex] {
        let all = artistsIndex()
        let grouped = Dictionary(grouping: all) { (a: ArtistID3) -> String in
            String(a.name.first.map(String.init)?.uppercased() ?? "#")
        }
        return grouped.keys.sorted().map { key in
            ArtistIndex(name: key, artist: grouped[key]!.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    func artist(id: String) async throws -> ArtistID3 {
        guard var a = artistsIndex().first(where: { $0.id == id }) else { throw LocalBackendError.notFound }
        let albums = albumsIndex().filter { $0.artistId == id }
        a = ArtistID3(id: a.id, name: a.name, albumCount: albums.count, coverArt: a.coverArt, album: albums)
        return a
    }

    func album(id: String) async throws -> AlbumID3 {
        guard let a = albumsIndex().first(where: { $0.id == id }) else { throw LocalBackendError.notFound }
        return a
    }

    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] {
        loadIfNeeded()
        return records.filter { $0.song.artistId == artistID }.map { DisplayableSong(from: $0.song, isDownloaded: true) }
    }

    func playlists() async throws -> [Playlist] { [] }

    func playlist(id: String) async throws -> PlaylistWithSongs { throw LocalBackendError.notFound }

    func search(_ query: String) async throws -> SearchResult3 {
        loadIfNeeded()
        let q = query.lowercased()
        let songs = records.map(\.song).filter { $0.title.lowercased().contains(q) || ($0.artist ?? "").lowercased().contains(q) }
        let albums = albumsIndex().filter { $0.name.lowercased().contains(q) || ($0.artist ?? "").lowercased().contains(q) }
        let artists = artistsIndex().filter { $0.name.lowercased().contains(q) }
        return try Self.makeSearchResult(artists: artists, albums: albums, songs: songs)
    }

    func coverArtURL(id: String, size: Int?) async -> URL? {
        let url = coversDir.appendingPathComponent("\(id).jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func streamURL(songId: String) async -> URL? {
        loadIfNeeded()
        guard let rec = records.first(where: { $0.song.id == songId }) else { return nil }
        return filesDir.appendingPathComponent(rec.relativePath)
    }

    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws {
        loadIfNeeded()
        for i in records.indices where songIds.contains(records[i].song.id) { records[i].starred = true }
        save()
    }

    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws {
        loadIfNeeded()
        for i in records.indices where songIds.contains(records[i].song.id) { records[i].starred = false }
        save()
    }

    func getStarred2() async throws -> Starred2 {
        loadIfNeeded()
        let songs = records.filter { $0.starred }.map(\.song)
        return try Self.makeStarred2(songs: songs)
    }

    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] { Array(albumsIndex().reversed().prefix(size)) }
    func allAlbums() async throws -> [AlbumID3] { albumsIndex() }
    func scrobble(songId: String, submission: Bool) async {}
    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] { Array(albumsIndex().prefix(size)) }
    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] { Array(albumsIndex().prefix(size)) }

    func randomSongs(size: Int) async throws -> [Song] {
        loadIfNeeded()
        return Array(records.map(\.song).shuffled().prefix(size))
    }

    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] {
        loadIfNeeded()
        return records.map(\.song).shuffled().prefix(targetSize).map { DisplayableSong(from: $0, isDownloaded: true) }
    }

    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] {
        loadIfNeeded()
        return records.map(\.song).filter { !excludedIds.contains($0.id) }.shuffled().prefix(targetSize)
            .map { DisplayableSong(from: $0, isDownloaded: true) }
    }

    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws {}
    func getPlayQueue() async throws -> SavedPlayQueue? { nil }
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo { throw LocalBackendError.unsupported }
    func getArtistMBID(forArtistID artistID: String) async throws -> String? { nil }
    func findArtist(byName name: String) async -> ArtistID3? {
        artistsIndex().first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func makeSearchResult(artists: [ArtistID3], albums: [AlbumID3], songs: [Song]) throws -> SearchResult3 {
        struct Payload: Encodable { let artist: [ArtistID3]; let album: [AlbumID3]; let song: [Song] }
        let data = try JSONEncoder().encode(Payload(artist: artists, album: albums, song: songs))
        return try JSONDecoder().decode(SearchResult3.self, from: data)
    }

    private static func makeStarred2(songs: [Song]) throws -> Starred2 {
        struct Payload: Encodable { let artist: [ArtistID3]; let album: [AlbumID3]; let song: [Song] }
        let data = try JSONEncoder().encode(Payload(artist: [], album: [], song: songs))
        return try JSONDecoder().decode(Starred2.self, from: data)
    }
}

enum LocalBackendError: Error { case notFound, unsupported }

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
