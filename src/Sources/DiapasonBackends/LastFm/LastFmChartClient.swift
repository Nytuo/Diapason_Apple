// Diapason — read-only Last.fm charts & genre stations for curated Discover playlists.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation

/// Fetches global charts and genre/mood tag stations from Last.fm. Reuses
/// `LBPlaylistTrack` (title + artist) so the existing resolve→play/download path
/// (library match, else YouTube) works unchanged.
enum LastFmChartClient {
    private static let base = "https://ws.audioscrobbler.com/2.0/"

    private static var apiKey: String {
        UserDefaults.standard.string(forKey: "diapason.lastfm.apiKey") ?? ""
    }

    static var isConfigured: Bool { !apiKey.isEmpty }

    private struct Resp: Decodable {
        struct Tracks: Decodable { let track: [Track]? }
        struct Track: Decodable {
            let name: String
            let artist: Artist
        }
        struct Artist: Decodable { let name: String }
        let tracks: Tracks?
    }

    static func topTracks(limit: Int = 100) async -> [LBPlaylistTrack] {
        await get([
            "method": "chart.getTopTracks",
            "limit": String(limit),
        ])
    }

    static func tagTopTracks(_ tag: String, limit: Int = 60) async -> [LBPlaylistTrack] {
        await get([
            "method": "tag.getTopTracks",
            "tag": tag,
            "limit": String(limit),
        ])
    }

    private static func get(_ params: [String: String]) async -> [LBPlaylistTrack] {
        guard !apiKey.isEmpty else { return [] }
        var comps = URLComponents(string: base)
        comps?.queryItems = ([
            "api_key": apiKey,
            "format": "json",
        ].merging(params) { _, new in new }).map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps?.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Diapason", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let resp = try? JSONDecoder().decode(Resp.self, from: data) else { return [] }
        return (resp.tracks?.track ?? []).map { LBPlaylistTrack(title: $0.name, artist: $0.artist.name) }
    }
}

struct CuratedStation: Identifiable, Hashable {
    enum Kind: Hashable {
        case top100
        case tag(String)
    }
    let id: String
    let name: String
    let kind: Kind

    static let all: [CuratedStation] = [
        CuratedStation(id: "top100", name: "Top 100 Global", kind: .top100),
        CuratedStation(id: "hip-hop", name: "Hip-Hop", kind: .tag("hip-hop")),
        CuratedStation(id: "rock", name: "Rock", kind: .tag("rock")),
        CuratedStation(id: "pop", name: "Pop", kind: .tag("pop")),
        CuratedStation(id: "electronic", name: "Electronic", kind: .tag("electronic")),
        CuratedStation(id: "rnb", name: "R&B", kind: .tag("rnb")),
        CuratedStation(id: "indie", name: "Indie", kind: .tag("indie")),
        CuratedStation(id: "jazz", name: "Jazz", kind: .tag("jazz")),
        CuratedStation(id: "metal", name: "Metal", kind: .tag("metal")),
        CuratedStation(id: "classical", name: "Classical", kind: .tag("classical")),
        CuratedStation(id: "dance", name: "Dance", kind: .tag("dance")),
        CuratedStation(id: "chill", name: "Chill", kind: .tag("chillout")),
        CuratedStation(id: "workout", name: "Workout", kind: .tag("workout")),
    ]

    func fetchTracks() async -> [LBPlaylistTrack] {
        switch kind {
        case .top100: return await LastFmChartClient.topTracks(limit: 100)
        case let .tag(tag): return await LastFmChartClient.tagTopTracks(tag)
        }
    }
}
