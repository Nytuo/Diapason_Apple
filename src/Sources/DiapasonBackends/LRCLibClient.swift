// Diapason — LRCLIB lyrics fallback (https://lrclib.net). Works for any backend.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic

struct LyricsFallback: Sendable {
    let artist: String
    let title: String
    let album: String?
    let durationSeconds: Int
}

enum LRCLibClient {
    private struct Response: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    static func fetch(_ m: LyricsFallback) async throws -> LyricsList {
        if let exact = try? await get(m), let list = build(exact, meta: m) { return list }
        if let searched = try? await search(m), let list = build(searched, meta: m) { return list }
        throw LyricsError.notFound
    }

    private static func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Diapason (https://github.com/Nytuo/Diapason_iOS)", forHTTPHeaderField: "User-Agent")
        return req
    }

    private static func get(_ m: LyricsFallback) async throws -> Response {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "artist_name", value: m.artist),
            URLQueryItem(name: "track_name", value: m.title),
            URLQueryItem(name: "album_name", value: m.album ?? m.title),
            URLQueryItem(name: "duration", value: String(m.durationSeconds)),
        ]
        let (data, resp) = try await URLSession.shared.data(for: request(comps.url!))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw LyricsError.notFound }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func search(_ m: LyricsFallback) async throws -> Response {
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: m.title),
            URLQueryItem(name: "artist_name", value: m.artist),
        ]
        let (data, resp) = try await URLSession.shared.data(for: request(comps.url!))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw LyricsError.notFound }
        let results = try JSONDecoder().decode([Response].self, from: data)
        guard let first = results.first(where: { ($0.syncedLyrics ?? $0.plainLyrics)?.isEmpty == false }) else {
            throw LyricsError.notFound
        }
        return first
    }

    private static func build(_ r: Response, meta: LyricsFallback) -> LyricsList? {
        if let synced = r.syncedLyrics, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty {
                let sl = StructuredLyrics(lang: "und", synced: true, line: lines,
                                          displayArtist: meta.artist, displayTitle: meta.title)
                return LyricsList(structuredLyrics: [sl])
            }
        }
        if let plain = r.plainLyrics, !plain.isEmpty {
            let lines = plain.split(separator: "\n", omittingEmptySubsequences: false).map { Line(value: String($0)) }
            let sl = StructuredLyrics(lang: "und", synced: false, line: lines,
                                      displayArtist: meta.artist, displayTitle: meta.title)
            return LyricsList(structuredLyrics: [sl])
        }
        return nil
    }

    private static func parseLRC(_ lrc: String) -> [Line] {
        var out: [Line] = []
        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            var idx = line.startIndex
            var stamps: [Int] = []
            while idx < line.endIndex, line[idx] == "[" {
                guard let close = line[idx...].firstIndex(of: "]") else { break }
                let tag = String(line[line.index(after: idx)..<close])
                if let ms = msFromTag(tag) { stamps.append(ms) }
                idx = line.index(after: close)
            }
            let text = String(line[idx...]).trimmingCharacters(in: .whitespaces)
            guard !stamps.isEmpty else { continue }
            for ms in stamps { out.append(Line(value: text, start: ms)) }
        }
        return out.sorted { ($0.start ?? 0) < ($1.start ?? 0) }
    }

    private static func msFromTag(_ tag: String) -> Int? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let min = Int(parts[0]) else { return nil }
        let secParts = parts[1].split(separator: ".")
        guard let sec = Int(secParts[0]) else { return nil }
        var ms = (min * 60 + sec) * 1000
        if secParts.count == 2 {
            let frac = String(secParts[1])
            if let f = Int(frac) { ms += frac.count == 2 ? f * 10 : f }
        }
        return ms
    }
}
