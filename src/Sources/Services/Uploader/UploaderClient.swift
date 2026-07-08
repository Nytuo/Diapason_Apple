// Diapason — client for the Diapason Uploader sidecar.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import CryptoKit
import Foundation

/// Pushes downloaded tracks into the user's music-server library via a
/// `diapason-uploader` sidecar (Navidrome/Plex expose no ingest API).
struct UploaderClient {
    static let shared = UploaderClient()

    enum Keys {
        static let enabled = "uploader_enabled"
        static let url = "uploader_url"
        static let token = "uploader_token"
        static let networkPolicy = "uploader_network_policy" // "local" | "internet"
    }

    private var defaults: UserDefaults { .standard }

    var isEnabled: Bool { defaults.bool(forKey: Keys.enabled) }
    var baseURL: String {
        (defaults.string(forKey: Keys.url) ?? "").trimmingCharacters(in: .whitespaces)
    }
    var token: String { defaults.string(forKey: Keys.token) ?? "" }
    var networkPolicy: String { defaults.string(forKey: Keys.networkPolicy) ?? "local" }

    var isReady: Bool {
        guard isEnabled, !baseURL.isEmpty else { return false }
        return Self.isAllowed(urlString: baseURL, policy: networkPolicy)
    }

    struct Metadata: Encodable {
        let artist: String
        let album: String
        let title: String
        let trackNumber: Int
        let discNumber: Int
        let year: Int
        let ext: String
    }

    /// Upload the file at `fileURL` for `song`. `ext` is the container extension
    /// without a dot (e.g. "m4a"). No-op when the uploader is disabled/blocked.
    func upload(
        songTitle: String,
        artist: String,
        album: String,
        trackNumber: Int?,
        fileURL: URL,
        ext: String
    ) async {
        guard isReady else { return }
        guard let base = normalizedBase(), let data = try? Data(contentsOf: fileURL) else { return }

        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if await exists(hash: hash, base: base) { return }

        let meta = Metadata(
            artist: artist, album: album, title: songTitle,
            trackNumber: trackNumber ?? 0, discNumber: 0, year: 0,
            ext: ext.isEmpty ? "m4a" : ext
        )
        guard let metaJSON = try? JSONEncoder().encode(meta) else { return }

        let boundary = "diapason.\(UUID().uuidString)"
        var body = Data()
        appendPart(&body, boundary: boundary, name: "metadata",
                   contentType: "application/json", data: metaJSON)
        appendFilePart(&body, boundary: boundary, name: "file",
                       filename: "track.\(meta.ext)", data: data)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: base.appendingPathComponent("api/v1/upload"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        _ = try? await URLSession.shared.upload(for: req, from: body)
    }

    private func exists(hash: String, base: URL) async -> Bool {
        var comps = URLComponents(url: base.appendingPathComponent("api/v1/exists"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "hash", value: hash)]
        guard let url = comps?.url else { return false }
        var req = URLRequest(url: url)
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return (obj["exists"] as? Bool) ?? false
    }

    private func normalizedBase() -> URL? {
        var s = baseURL
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    private func appendPart(_ body: inout Data, boundary: String, name: String,
                            contentType: String, data: Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    private func appendFilePart(_ body: inout Data, boundary: String, name: String,
                                filename: String, data: Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    /// IPv4/IPv6 private + loopback + `.local` hostnames pass "local"; everything
    /// passes "internet".
    static func isAllowed(urlString: String, policy: String) -> Bool {
        if policy == "internet" { return true }
        guard let host = URLComponents(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            return false
        }
        if host == "localhost" || host.hasSuffix(".local") { return true }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") { return true }
        if host.range(of: #"^172\.(1[6-9]|2\d|3[01])\."#, options: .regularExpression) != nil { return true }
        if host == "::1" || host.hasPrefix("fd") || host.hasPrefix("fc") { return true }
        return false
    }
}
