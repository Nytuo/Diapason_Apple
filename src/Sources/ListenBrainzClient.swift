import Foundation

// MARK: - Models

struct LBFreshRelease: Identifiable {
    let id: String          // release_mbid
    let releaseName: String
    let artistName: String
    let releaseDate: String?
    let coverArtURL: URL?
}

// MARK: - Decodable helpers (internal)

private struct LBFreshReleasesResponse: Decodable {
    struct Payload: Decodable {
        let releases: [LBReleaseRaw]
    }
    let payload: Payload
}

private struct LBReleaseRaw: Decodable {
    let release_mbid: String
    let release_name: String
    let artist_credit_name: String
    let release_date: String?
    let caa_id: Int64?
    let caa_release_mbid: String?
}

// MARK: - Client

class ListenBrainzClient {
    static let shared = ListenBrainzClient()
    private let session = URLSession.shared
    private let userAgent = "Diapason iOS/1.0 (music player)"

    func getFreshReleases(days: Int = 7, limit: Int = 30) async -> [LBFreshRelease] {
        var components = URLComponents(string: "https://api.listenbrainz.org/1/explore/fresh-releases")!
        components.queryItems = [
            URLQueryItem(name: "days",    value: "\(days)"),
            URLQueryItem(name: "sort",    value: "release_date"),
            URLQueryItem(name: "past",    value: "true"),
            URLQueryItem(name: "future",  value: "false")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(LBFreshReleasesResponse.self, from: data)
            return decoded.payload.releases
                .prefix(limit)
                .map { raw in
                    let coverURL = coverArtURL(mbid: raw.caa_release_mbid ?? raw.release_mbid)
                    return LBFreshRelease(
                        id: raw.release_mbid,
                        releaseName: raw.release_name,
                        artistName: raw.artist_credit_name,
                        releaseDate: raw.release_date,
                        coverArtURL: coverURL
                    )
                }
        } catch {
            print("ListenBrainz fresh-releases error: \(error)")
            return []
        }
    }

    private func coverArtURL(mbid: String) -> URL? {
        URL(string: "https://coverartarchive.org/release/\(mbid)/front-250")
    }

    // MARK: - Discovery

    private func headers(token: String?) -> [String: String] {
        var h = ["User-Agent": userAgent]
        if let token, !token.isEmpty { h["Authorization"] = "Token \(token)" }
        return h
    }

    private func getData(_ urlString: String, token: String?) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        for (k, v) in headers(token: token) { request.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        } catch { return nil }
    }

    private func extractMbid(from identifiers: [String]) -> String? {
        let pattern = "(?:recording|playlist)/([0-9a-fA-F-]{36})"
        let regex = try? NSRegularExpression(pattern: pattern)
        for id in identifiers {
            let range = NSRange(id.startIndex..., in: id)
            if let m = regex?.firstMatch(in: id, range: range),
               let r = Range(m.range(at: 1), in: id) {
                return String(id[r])
            }
        }
        return nil
    }

    private func fetchPlaylists(_ urlString: String, token: String?, kind: DiscoveryKind) async -> [DiscoveryPlaylist] {
        guard let data = await getData(urlString, token: token),
              let decoded = try? JSONDecoder().decode(LBCreatedForResp.self, from: data) else { return [] }
        return decoded.playlists.compactMap { env in
            guard let mbid = extractMbid(from: [env.playlist.identifier ?? ""]) else { return nil }
            let desc = env.playlist.annotation?
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            return DiscoveryPlaylist(
                id: "listenbrainz:\(mbid)",
                source: .listenbrainz,
                kind: kind,
                sourceId: mbid,
                name: env.playlist.title ?? "Playlist",
                description: desc.map { String($0.prefix(140)) }
            )
        }
    }

    /// "Created for you" recommendation playlists (Weekly Jams, Daily Jams, …).
    func createdForPlaylists(user: String, token: String?) async -> [DiscoveryPlaylist] {
        await fetchPlaylists("https://api.listenbrainz.org/1/user/\(user)/playlists/createdfor", token: token, kind: .discover)
    }

    /// The user's own (recovered) playlists.
    func userPlaylists(user: String, token: String?) async -> [DiscoveryPlaylist] {
        await fetchPlaylists("https://api.listenbrainz.org/1/user/\(user)/playlists", token: token, kind: .recovered)
    }

    /// Submit a "now playing" or completed listen.
    func submitListen(token: String, listenType: String, artist: String, track: String,
                      album: String, listenedAt: Int?) async {
        guard let url = URL(string: "https://api.listenbrainz.org/1/submit-listens") else { return }
        var meta: [String: Any] = ["artist_name": artist, "track_name": track]
        if !album.isEmpty { meta["release_name"] = album }
        var listen: [String: Any] = ["track_metadata": meta]
        if listenType == "single", let listenedAt { listen["listened_at"] = listenedAt }
        let payload: [String: Any] = ["listen_type": listenType, "payload": [listen]]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        _ = try? await session.data(for: request)
    }

    func playlistTracks(mbid: String, token: String?) async -> [DiscoveryTrack] {
        guard let data = await getData("https://api.listenbrainz.org/1/playlist/\(mbid)", token: token),
              let decoded = try? JSONDecoder().decode(LBSinglePlaylistResp.self, from: data) else { return [] }
        return decoded.playlist.track?.map { t in
            DiscoveryTrack(
                id: discoveryTrackId(.listenbrainz, t.creator ?? "", t.title ?? ""),
                title: t.title ?? "",
                artist: t.creator ?? "",
                mbid: extractMbid(from: t.identifier ?? [])
            )
        } ?? []
    }

    func topRecordings(user: String, token: String?) async -> [DiscoveryTrack] {
        guard let data = await getData("https://api.listenbrainz.org/1/stats/user/\(user)/recordings?count=50&range=month", token: token),
              let decoded = try? JSONDecoder().decode(LBStatsResp.self, from: data) else { return [] }
        return decoded.payload.recordings.map { rec in
            DiscoveryTrack(
                id: discoveryTrackId(.listenbrainz, rec.artist_name ?? "", rec.track_name ?? ""),
                title: rec.track_name ?? "",
                artist: rec.artist_name ?? "",
                mbid: rec.recording_mbid,
                coverURL: rec.caa_release_mbid.map { "https://coverartarchive.org/release/\($0)/front-250" }
            )
        }
    }
}

// MARK: - Discovery wire types

private struct LBCreatedForResp: Decodable { let playlists: [LBPlaylistEnvelope] }
private struct LBPlaylistEnvelope: Decodable { let playlist: LBPlaylistMeta }
private struct LBPlaylistMeta: Decodable {
    let identifier: String?
    let title: String?
    let annotation: String?
    let track: [LBJspfTrack]?
}
private struct LBSinglePlaylistResp: Decodable { let playlist: LBPlaylistMeta }
private struct LBJspfTrack: Decodable {
    let title: String?
    let creator: String?
    let identifier: [String]?
}
private struct LBStatsResp: Decodable {
    struct Payload: Decodable { let recordings: [LBRecording] }
    let payload: Payload
}
private struct LBRecording: Decodable {
    let track_name: String?
    let artist_name: String?
    let recording_mbid: String?
    let caa_release_mbid: String?
}
