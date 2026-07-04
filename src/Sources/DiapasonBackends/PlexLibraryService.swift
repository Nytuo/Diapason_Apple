// Diapason — Plex backend adapter for the Cassette UI.
// Implements Cassette's LibraryServiceProtocol against a Plex Media Server,
// producing SwiftSonic model types so the forked Cassette views work unchanged.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.
// Consumes Cassette (MPL-2.0) protocols; see LICENSE-Cassette / NOTICE-Cassette.

import Foundation
import SwiftSonic

actor PlexLibraryService: LibraryServiceProtocol {
    private let serverService: any ServerServiceProtocol
    private var cachedSectionId: String?

    init(serverService: any ServerServiceProtocol) {
        self.serverService = serverService
    }

    private func connection() async throws -> (base: String, token: String) {
        let base = await MainActor.run { serverService.state.activeServer?.baseURL }
        guard let base, !base.isEmpty else { throw PlexBackendError.notConfigured }
        let creds = try await serverService.activeCredentials()
        return (base.trimmingCharacters(in: CharacterSet(charactersIn: "/")), creds.password)
    }

    private func url(_ path: String, base: String, token: String) -> URL? {
        let sep = path.contains("?") ? "&" : "?"
        return URL(string: "\(base)\(path)\(sep)X-Plex-Token=\(token)")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (base, token) = try await connection()
        guard let url = url(path, base: base, token: token) else { throw PlexBackendError.notConfigured }
        var req = URLRequest(url: url)
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sectionId() async throws -> String {
        if let cachedSectionId { return cachedSectionId }
        let container: PMContainer<PMSections> = try await get("/library/sections")
        guard let section = container.mediaContainer.directory.first(where: { $0.type == "artist" || $0.type == "music" }) else {
            throw PlexBackendError.noMusicSection
        }
        cachedSectionId = section.key
        return section.key
    }

    func allAlbums() async throws -> [AlbumID3] {
        let sec = try await sectionId()
        let c: PMContainer<PMMeta> = try await get("/library/sections/\(sec)/albums")
        return c.mediaContainer.metadata.map { $0.asAlbum() }
    }

    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] {
        let sec = try await sectionId()
        let c: PMContainer<PMMeta> = try await get("/library/sections/\(sec)/albums?sort=addedAt:desc")
        return Array(c.mediaContainer.metadata.prefix(size).map { $0.asAlbum() })
    }

    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] {
        let sec = try await sectionId()
        let c: PMContainer<PMMeta> = try await get("/library/sections/\(sec)/albums?sort=lastViewedAt:desc")
        return Array(c.mediaContainer.metadata.prefix(size).map { $0.asAlbum() })
    }

    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] {
        let sec = try await sectionId()
        let c: PMContainer<PMMeta> = try await get("/library/sections/\(sec)/albums?sort=viewCount:desc")
        return Array(c.mediaContainer.metadata.prefix(size).map { $0.asAlbum() })
    }

    func artists() async throws -> [ArtistIndex] {
        let sec = try await sectionId()
        let c: PMContainer<PMMeta> = try await get("/library/sections/\(sec)/all")
        let all = c.mediaContainer.metadata.map { ArtistID3(id: $0.ratingKey, name: $0.title, coverArt: $0.thumb) }
        let grouped = Dictionary(grouping: all) { String($0.name.first.map(String.init)?.uppercased() ?? "#") }
        return grouped.keys.sorted().map { key in
            ArtistIndex(name: key, artist: grouped[key]!.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
    }

    func artist(id: String) async throws -> ArtistID3 {
        async let childrenC: PMContainer<PMMeta> = get("/library/metadata/\(id)/children")
        async let metaC: PMContainer<PMMeta> = get("/library/metadata/\(id)")
        let albums = try await childrenC.mediaContainer.metadata.map { $0.asAlbum() }
        let meta = try await metaC.mediaContainer.metadata.first
        return ArtistID3(id: id, name: meta?.title ?? "Unknown Artist", albumCount: albums.count, coverArt: meta?.thumb, album: albums)
    }

    func album(id: String) async throws -> AlbumID3 {
        async let childrenC: PMContainer<PMMeta> = get("/library/metadata/\(id)/children")
        async let metaC: PMContainer<PMMeta> = get("/library/metadata/\(id)")
        let songs = try await childrenC.mediaContainer.metadata.map { $0.asSong() }
        let meta = try await metaC.mediaContainer.metadata.first
        let total = songs.reduce(0) { $0 + ($1.duration ?? 0) }
        return AlbumID3(
            id: id, name: meta?.title ?? "Unknown Album", songCount: songs.count, duration: total,
            artist: meta?.parentTitle, artistId: meta?.parentRatingKey, coverArt: meta?.thumb, year: meta?.year, song: songs
        )
    }

    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] {
        let artist = try await artist(id: artistID)
        var tracks: [DisplayableSong] = []
        for album in artist.album ?? [] {
            if let full = try? await self.album(id: album.id), let songs = full.song {
                tracks.append(contentsOf: songs.map { DisplayableSong(from: $0) })
            }
        }
        return tracks
    }

    func playlists() async throws -> [Playlist] {
        let c: PMContainer<PMMeta> = try await get("/playlists")
        return c.mediaContainer.metadata.filter { $0.playlistType == "audio" }.map {
            Playlist(id: $0.ratingKey, name: $0.title, songCount: $0.leafCount ?? 0, duration: ($0.duration ?? 0) / 1000, coverArt: $0.composite ?? $0.thumb)
        }
    }

    func playlist(id: String) async throws -> PlaylistWithSongs {
        async let itemsC: PMContainer<PMMeta> = get("/playlists/\(id)/items")
        async let metaC: PMContainer<PMMeta> = get("/playlists/\(id)")
        let songs = try await itemsC.mediaContainer.metadata.map { $0.asSong() }
        let meta = try await metaC.mediaContainer.metadata.first
        return PlaylistWithSongs(
            id: id, name: meta?.title ?? "Playlist", songCount: songs.count,
            duration: songs.reduce(0) { $0 + ($1.duration ?? 0) }, coverArt: meta?.composite ?? meta?.thumb, entry: songs
        )
    }

    func search(_ query: String) async throws -> SearchResult3 {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let c: PMContainer<PMMeta> = try await get("/library/all?type=10&query=\(q)")
        let songs = c.mediaContainer.metadata.map { $0.asSong() }
        return try makeSearchResult(songs: songs)
    }

    func coverArtURL(id: String, size: Int?) async -> URL? {
        guard id.hasPrefix("/"), let (base, token) = try? await connection() else {
            return id.hasPrefix("http") ? URL(string: id) : nil
        }
        return url(id, base: base, token: token)
    }

    func streamURL(songId: String) async -> URL? {
        guard songId.hasPrefix("/"), let (base, token) = try? await connection() else { return nil }
        return url(songId, base: base, token: token)
    }

    func randomSongs(size: Int) async throws -> [Song] {
        let albums = try await allAlbums().shuffled().prefix(max(1, size / 8))
        var songs: [Song] = []
        for a in albums {
            if let full = try? await album(id: a.id), let s = full.song { songs.append(contentsOf: s) }
            if songs.count >= size { break }
        }
        return Array(songs.shuffled().prefix(size))
    }

    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] {
        try await randomSongs(size: targetSize).map { DisplayableSong(from: $0) }
    }

    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] {
        try await randomSongs(size: targetSize).filter { !excludedIds.contains($0.id) }.map { DisplayableSong(from: $0) }
    }

    func findArtist(byName name: String) async -> ArtistID3? {
        guard let indexes = try? await artists() else { return nil }
        return indexes.flatMap { $0.artist }.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws {}
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws {}
    func getStarred2() async throws -> Starred2 { try makeStarred2() }
    func scrobble(songId: String, submission: Bool) async {}
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws {}
    func getPlayQueue() async throws -> SavedPlayQueue? { nil }
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo { throw PlexBackendError.unsupported }
    func getArtistMBID(forArtistID artistID: String) async throws -> String? { nil }

    private func makeSearchResult(songs: [Song]) throws -> SearchResult3 {
        struct Payload: Encodable { let artist: [ArtistID3]; let album: [AlbumID3]; let song: [Song] }
        let data = try JSONEncoder().encode(Payload(artist: [], album: [], song: songs))
        return try JSONDecoder().decode(SearchResult3.self, from: data)
    }
    private func makeStarred2() throws -> Starred2 {
        struct Payload: Encodable { let artist: [ArtistID3]; let album: [AlbumID3]; let song: [Song] }
        let data = try JSONEncoder().encode(Payload(artist: [], album: [], song: []))
        return try JSONDecoder().decode(Starred2.self, from: data)
    }
}

enum PlexBackendError: Error { case notConfigured, noMusicSection, unsupported }

private struct PMContainer<T: Decodable>: Decodable {
    let mediaContainer: T
    enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" }
}
private struct PMSections: Decodable {
    let directory: [PMSection]
    enum CodingKeys: String, CodingKey { case directory = "Directory" }
}
private struct PMSection: Decodable { let key: String; let type: String }
private struct PMMeta: Decodable {
    let metadata: [PMItem]
    enum CodingKeys: String, CodingKey { case metadata = "Metadata" }
}
private struct PMItem: Decodable {
    let ratingKey: String
    let title: String
    let parentTitle: String?
    let grandparentTitle: String?
    let parentRatingKey: String?
    let grandparentRatingKey: String?
    let thumb: String?
    let composite: String?
    let year: Int?
    let index: Int?
    let duration: Int?
    let playlistType: String?
    let leafCount: Int?
    let media: [PMMedia]?

    func asAlbum() -> AlbumID3 {
        AlbumID3(id: ratingKey, name: title, songCount: leafCount ?? 0, duration: (duration ?? 0) / 1000,
                 artist: parentTitle, artistId: parentRatingKey, coverArt: thumb, year: year)
    }
    func asSong() -> Song {
        let partKey = media?.first?.part.first?.key ?? ""
        return Song(
            id: partKey, title: title, album: parentTitle, artist: grandparentTitle,
            track: index, year: year, coverArt: thumb, duration: (duration ?? 0) / 1000,
            bitRate: media?.first?.bitrate, albumId: parentRatingKey, artistId: grandparentRatingKey
        )
    }
}
private struct PMMedia: Decodable {
    let bitrate: Int?
    let part: [PMPart]
    enum CodingKeys: String, CodingKey { case bitrate, part = "Part" }
}
private struct PMPart: Decodable { let key: String }
