// Diapason — Last.fm scrobbling (audioscrobbler 2.0).
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation
import CryptoKit

actor LastFmScrobbler {
    static let shared = LastFmScrobbler()

    private let base = "https://ws.audioscrobbler.com/2.0/"
    private let d = UserDefaults.standard
    private enum K {
        static let apiKey = "diapason.lastfm.apiKey"
        static let secret = "diapason.lastfm.secret"
        static let session = "diapason.lastfm.session"
        static let username = "diapason.lastfm.username"
        static let enabled = "diapason.lastfm.enabled"
    }

    nonisolated var apiKey: String { UserDefaults.standard.string(forKey: K.apiKey) ?? "" }
    nonisolated var apiSecret: String { UserDefaults.standard.string(forKey: K.secret) ?? "" }
    nonisolated var username: String? { UserDefaults.standard.string(forKey: K.username) }
    nonisolated var isConnected: Bool { UserDefaults.standard.string(forKey: K.session)?.isEmpty == false }
    nonisolated var isEnabled: Bool { UserDefaults.standard.bool(forKey: K.enabled) }

    nonisolated func setCredentials(apiKey: String, secret: String) {
        UserDefaults.standard.set(apiKey, forKey: K.apiKey)
        UserDefaults.standard.set(secret, forKey: K.secret)
    }
    nonisolated func setEnabled(_ on: Bool) { UserDefaults.standard.set(on, forKey: K.enabled) }
    nonisolated func disconnect() {
        UserDefaults.standard.removeObject(forKey: K.session)
        UserDefaults.standard.removeObject(forKey: K.username)
        UserDefaults.standard.set(false, forKey: K.enabled)
    }

    private var sessionKey: String? { d.string(forKey: K.session) }

    private func sign(_ params: [String: String]) -> String {
        let buf = params.sorted { $0.key < $1.key }.map { $0.key + $0.value }.joined()
        let digest = Insecure.MD5.hash(data: Data((buf + apiSecret).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func getToken() async -> String? {
        let params = ["method": "auth.getToken", "api_key": apiKey]
        let sig = sign(params)
        guard let url = URL(string: "\(base)?method=auth.getToken&api_key=\(apiKey)&api_sig=\(sig)&format=json") else { return nil }
        struct R: Decodable { let token: String }
        return (try? await getJSON(R.self, url))?.token
    }

    nonisolated func authURL(token: String) -> URL? {
        URL(string: "https://www.last.fm/api/auth/?api_key=\(apiKey)&token=\(token)")
    }

    func completeAuth(token: String) async -> Bool {
        let params = ["method": "auth.getSession", "api_key": apiKey, "token": token]
        let sig = sign(params)
        guard let url = URL(string: "\(base)?method=auth.getSession&api_key=\(apiKey)&token=\(token)&api_sig=\(sig)&format=json") else { return false }
        struct Session: Decodable { let name: String; let key: String }
        struct R: Decodable { let session: Session }
        guard let r = try? await getJSON(R.self, url) else { return false }
        d.set(r.session.key, forKey: K.session)
        d.set(r.session.name, forKey: K.username)
        d.set(true, forKey: K.enabled)
        return true
    }

    func updateNowPlaying(song: DisplayableSong) async {
        guard isEnabled, let sk = sessionKey, let artist = song.artist, !artist.isEmpty else { return }
        var p = ["method": "track.updateNowPlaying", "api_key": apiKey, "sk": sk,
                 "artist": artist, "track": song.title]
        if let album = song.albumName { p["album"] = album }
        if song.duration > 0 { p["duration"] = String(Int(song.duration)) }
        await post(p)
    }

    func scrobble(song: DisplayableSong, startedAt: Date) async {
        guard isEnabled, let sk = sessionKey, let artist = song.artist, !artist.isEmpty else { return }
        var p = ["method": "track.scrobble", "api_key": apiKey, "sk": sk,
                 "artist": artist, "track": song.title,
                 "timestamp": String(Int(startedAt.timeIntervalSince1970))]
        if let album = song.albumName { p["album"] = album }
        await post(p)
    }

    private func post(_ params: [String: String]) async {
        var all = params
        all["api_sig"] = sign(all)
        all["format"] = "json"
        var req = URLRequest(url: URL(string: base)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = all.map { "\($0.key)=\(($0.value).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        _ = try? await URLSession.shared.data(for: req)
    }

    private func getJSON<T: Decodable>(_ type: T.Type, _ url: URL) async throws -> T {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
