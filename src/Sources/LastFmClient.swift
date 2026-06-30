import Foundation
import CryptoKit

struct LastFmSession {
    let key: String
    let name: String
}

// MARK: - Wire types

private struct LfmImage: Decodable { let text: String?; let size: String?
    enum CodingKeys: String, CodingKey { case text = "#text"; case size }
}
private struct LfmArtist: Decodable { let name: String? }
private struct LfmTrackRaw: Decodable {
    let name: String?
    let artist: LfmArtist?
    let mbid: String?
    let image: [LfmImage]?
}
private struct LfmChart: Decodable { let track: [LfmTrackRaw]? }
private struct LfmChartResp: Decodable { let tracks: LfmChart? }
private struct LfmTopResp: Decodable { let toptracks: LfmChart? }
private struct LfmLovedResp: Decodable { let lovedtracks: LfmChart? }
private struct LfmSimilarResp: Decodable { let similartracks: LfmChart? }
private struct LfmTokenResp: Decodable { let token: String? }
private struct LfmSessionRaw: Decodable { let key: String?; let name: String? }
private struct LfmSessionResp: Decodable { let session: LfmSessionRaw? }

// MARK: - Client

final class LastFmClient {
    static let shared = LastFmClient()
    private let session = URLSession.shared
    private let base = "https://ws.audioscrobbler.com/2.0/"

    private func bestImage(_ images: [LfmImage]?) -> String? {
        guard let images else { return nil }
        for size in ["extralarge", "large", "medium", "small"] {
            if let hit = images.first(where: { $0.size == size && !($0.text ?? "").isEmpty }) {
                return hit.text
            }
        }
        return images.first(where: { !($0.text ?? "").isEmpty })?.text
    }

    private func toTrack(_ t: LfmTrackRaw) -> DiscoveryTrack {
        let artist = t.artist?.name ?? ""
        let title = t.name ?? ""
        return DiscoveryTrack(
            id: discoveryTrackId(.lastfm, artist, title),
            title: title,
            artist: artist,
            mbid: (t.mbid?.isEmpty == false) ? t.mbid : nil,
            coverURL: bestImage(t.image)
        )
    }

    private func url(_ method: String, _ apiKey: String, _ params: [String: String]) -> URL? {
        var comps = URLComponents(string: base)!
        var items = [URLQueryItem(name: "method", value: method),
                     URLQueryItem(name: "api_key", value: apiKey),
                     URLQueryItem(name: "format", value: "json")]
        for (k, v) in params { items.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = items
        return comps.url
    }

    private func get<T: Decodable>(_ type: T.Type, _ url: URL?) async -> T? {
        guard let url else { return nil }
        do {
            let (data, resp) = try await session.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch { return nil }
    }

    func chartTopTracks(apiKey: String) async -> [DiscoveryTrack] {
        (await get(LfmChartResp.self, url("chart.getTopTracks", apiKey, ["limit": "50"])))?
            .tracks?.track?.map(toTrack) ?? []
    }

    func userTopTracks(apiKey: String, user: String) async -> [DiscoveryTrack] {
        (await get(LfmTopResp.self, url("user.getTopTracks", apiKey, ["user": user, "limit": "50", "period": "1month"])))?
            .toptracks?.track?.map(toTrack) ?? []
    }

    func userLovedTracks(apiKey: String, user: String) async -> [DiscoveryTrack] {
        (await get(LfmLovedResp.self, url("user.getLovedTracks", apiKey, ["user": user, "limit": "50"])))?
            .lovedtracks?.track?.map(toTrack) ?? []
    }

    func userMix(apiKey: String, user: String) async -> [DiscoveryTrack] {
        guard let seed = (await get(LfmTopResp.self, url("user.getTopTracks", apiKey, ["user": user, "limit": "1", "period": "3month"])))?
            .toptracks?.track?.first,
            let seedArtist = seed.artist?.name, let seedName = seed.name else { return [] }
        return (await get(LfmSimilarResp.self, url("track.getSimilar", apiKey, ["artist": seedArtist, "track": seedName, "limit": "50"])))?
            .similartracks?.track?.map(toTrack) ?? []
    }

    // MARK: - Web auth (signed)

    /// api_sig = md5(sorted "keyvalue…" + secret), excluding format/callback.
    private func sign(_ params: [String: String], secret: String) -> String {
        let buf = params.keys.sorted()
            .filter { $0 != "format" && $0 != "callback" }
            .map { "\($0)\(params[$0]!)" }
            .joined()
        let digest = Insecure.MD5.hash(data: Data((buf + secret).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func getAuthToken(apiKey: String, apiSecret: String) async -> String? {
        let params = ["method": "auth.getToken", "api_key": apiKey]
        let sig = sign(params, secret: apiSecret)
        let u = URL(string: "\(base)?method=auth.getToken&api_key=\(apiKey)&api_sig=\(sig)&format=json")
        return (await get(LfmTokenResp.self, u))?.token
    }

    func authURL(apiKey: String, token: String) -> URL? {
        URL(string: "https://www.last.fm/api/auth/?api_key=\(apiKey)&token=\(token)")
    }

    // MARK: - Scrobbling (signed form POST)

    private func signedPost(method: String, apiKey: String, apiSecret: String,
                            sessionKey: String, params: [String: String]) async {
        var all = params
        all["method"] = method
        all["api_key"] = apiKey
        all["sk"] = sessionKey
        all["api_sig"] = sign(all, secret: apiSecret)
        all["format"] = "json"

        var comps = URLComponents()
        comps.queryItems = all.map { URLQueryItem(name: $0.key, value: $0.value) }
        let bodyString = comps.percentEncodedQuery ?? ""

        guard let url = URL(string: base) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)
        _ = try? await session.data(for: request)
    }

    func updateNowPlaying(apiKey: String, apiSecret: String, sessionKey: String,
                          artist: String, track: String, album: String, durationSec: Int?) async {
        var params = ["artist": artist, "track": track]
        if !album.isEmpty { params["album"] = album }
        if let d = durationSec, d > 0 { params["duration"] = String(d) }
        await signedPost(method: "track.updateNowPlaying", apiKey: apiKey, apiSecret: apiSecret, sessionKey: sessionKey, params: params)
    }

    func scrobble(apiKey: String, apiSecret: String, sessionKey: String,
                  artist: String, track: String, album: String, timestamp: Int) async {
        var params = ["artist": artist, "track": track, "timestamp": String(timestamp)]
        if !album.isEmpty { params["album"] = album }
        await signedPost(method: "track.scrobble", apiKey: apiKey, apiSecret: apiSecret, sessionKey: sessionKey, params: params)
    }

    func getSession(apiKey: String, apiSecret: String, token: String) async -> LastFmSession? {
        let params = ["method": "auth.getSession", "api_key": apiKey, "token": token]
        let sig = sign(params, secret: apiSecret)
        let u = URL(string: "\(base)?method=auth.getSession&api_key=\(apiKey)&token=\(token)&api_sig=\(sig)&format=json")
        guard let raw = (await get(LfmSessionResp.self, u))?.session,
              let key = raw.key else { return nil }
        return LastFmSession(key: key, name: raw.name ?? "")
    }
}
