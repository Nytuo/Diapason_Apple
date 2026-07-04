// Diapason — read-only ListenBrainz playlist fetching (Weekly Jams, Daily Jams, etc.)
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation

struct LBPlaylistSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
}

struct LBPlaylistTrack: Hashable {
    let title: String
    let artist: String
}

enum LBPlaylistClient {
    private struct ListResponse: Decodable { let playlists: [Wrapper] }
    private struct Wrapper: Decodable { let playlist: PlaylistDTO }
    private struct SingleResponse: Decodable { let playlist: PlaylistDTO }
    private struct PlaylistDTO: Decodable {
        let title: String?
        let identifier: String?
        let annotation: String?
        let track: [TrackDTO]?
    }
    private struct TrackDTO: Decodable {
        let title: String?
        let creator: String?
    }

    static func createdFor(username: String) async -> [LBPlaylistSummary] {
        guard let url = URL(string: "https://api.listenbrainz.org/1/user/\(username)/playlists/createdfor") else { return [] }
        guard let resp: ListResponse = try? await get(url) else { return [] }
        return resp.playlists.compactMap { w in
            guard let mbid = mbid(from: w.playlist.identifier) else { return nil }
            return LBPlaylistSummary(id: mbid, title: w.playlist.title ?? "Playlist", description: w.playlist.annotation)
        }
    }

    static func tracks(playlistMbid: String) async -> [LBPlaylistTrack] {
        guard let url = URL(string: "https://api.listenbrainz.org/1/playlist/\(playlistMbid)") else { return [] }
        guard let resp: SingleResponse = try? await get(url) else { return [] }
        return (resp.playlist.track ?? []).compactMap { t in
            guard let title = t.title, let artist = t.creator else { return nil }
            return LBPlaylistTrack(title: title, artist: artist)
        }
    }

    private static func get<T: Decodable>(_ url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue("Diapason", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func mbid(from identifier: String?) -> String? {
        guard let identifier else { return nil }
        let parts = identifier.split(separator: "/").map(String.init)
        let candidate = parts.last ?? identifier
        return candidate.count == 36 ? candidate : nil
    }
}
