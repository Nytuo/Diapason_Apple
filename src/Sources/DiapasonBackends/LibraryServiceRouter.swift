// Diapason — routes Cassette's LibraryServiceProtocol calls to the correct
// backend adapter (Subsonic / Plex / Local) based on the active server's kind.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.
// Consumes Cassette (MPL-2.0) protocols; see LICENSE-Cassette / NOTICE-Cassette.

import Foundation
import SwiftSonic

final class LibraryServiceRouter: LibraryServiceProtocol {
    private let subsonic: any LibraryServiceProtocol
    private let plex: any LibraryServiceProtocol
    private let local: any LibraryServiceProtocol
    private let serverState: ServerState

    init(subsonic: any LibraryServiceProtocol,
         plex: any LibraryServiceProtocol,
         local: any LibraryServiceProtocol,
         serverState: ServerState) {
        self.subsonic = subsonic
        self.plex = plex
        self.local = local
        self.serverState = serverState
    }

    private func svc() async -> any LibraryServiceProtocol {
        let kind = await MainActor.run { serverState.activeServer?.backendKind ?? "subsonic" }
        switch kind {
        case "plex":  return plex
        case "local": return local
        default:       return subsonic
        }
    }

    func artists() async throws -> [ArtistIndex] { try await svc().artists() }
    func artist(id: String) async throws -> ArtistID3 { try await svc().artist(id: id) }
    func album(id: String) async throws -> AlbumID3 { try await svc().album(id: id) }
    func fetchAllTracks(forArtistID artistID: String) async throws -> [DisplayableSong] { try await svc().fetchAllTracks(forArtistID: artistID) }
    func playlists() async throws -> [Playlist] { try await svc().playlists() }
    func playlist(id: String) async throws -> PlaylistWithSongs { try await svc().playlist(id: id) }
    func search(_ query: String) async throws -> SearchResult3 { try await svc().search(query) }
    func coverArtURL(id: String, size: Int?) async -> URL? {
        if id.hasPrefix("ytimg:") {
            let videoId = String(id.dropFirst("ytimg:".count))
            return URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")
        }
        return await svc().coverArtURL(id: id, size: size)
    }
    func streamURL(songId: String) async -> URL? { await svc().streamURL(songId: songId) }
    func star(songIds: [String], albumIds: [String], artistIds: [String]) async throws { try await svc().star(songIds: songIds, albumIds: albumIds, artistIds: artistIds) }
    func unstar(songIds: [String], albumIds: [String], artistIds: [String]) async throws { try await svc().unstar(songIds: songIds, albumIds: albumIds, artistIds: artistIds) }
    func getStarred2() async throws -> Starred2 { try await svc().getStarred2() }
    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] { try await svc().recentlyAddedAlbums(size: size) }
    func allAlbums() async throws -> [AlbumID3] { try await svc().allAlbums() }
    func scrobble(songId: String, submission: Bool) async { await svc().scrobble(songId: songId, submission: submission) }
    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] { try await svc().recentlyPlayedAlbums(size: size) }
    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] { try await svc().mostPlayedAlbums(size: size) }
    func randomSongs(size: Int) async throws -> [Song] { try await svc().randomSongs(size: size) }
    func smartShuffleQueue(targetSize: Int) async throws -> [DisplayableSong] { try await svc().smartShuffleQueue(targetSize: targetSize) }
    func similarBackfillQueue(targetSize: Int, excludedIds: Set<String>) async throws -> [DisplayableSong] { try await svc().similarBackfillQueue(targetSize: targetSize, excludedIds: excludedIds) }
    func savePlayQueue(songIds: [String], currentIndex: Int, positionSeconds: Double) async throws { try await svc().savePlayQueue(songIds: songIds, currentIndex: currentIndex, positionSeconds: positionSeconds) }
    func getPlayQueue() async throws -> SavedPlayQueue? { try await svc().getPlayQueue() }
    func getArtistInfo(forArtistID artistID: String, count: Int) async throws -> ArtistInfo { try await svc().getArtistInfo(forArtistID: artistID, count: count) }
    func getArtistMBID(forArtistID artistID: String) async throws -> String? { try await svc().getArtistMBID(forArtistID: artistID) }
    func findArtist(byName name: String) async -> ArtistID3? { await svc().findArtist(byName: name) }
}
