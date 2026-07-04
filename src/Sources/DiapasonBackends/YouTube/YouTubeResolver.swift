// Diapason — resolves (artist, title) to a playable audio stream via YouTube, so
// recommended tracks not in the user's library are still playable.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation
#if canImport(YouTubeKit)
import YouTubeKit
#endif

struct ResolvedAudio {
    let url: URL
    let title: String
}

struct YouTubeResult: Identifiable, Hashable {
    let videoId: String
    let title: String
    let author: String
    var id: String { videoId }
}

enum YouTubeID {
    static let prefix = "yt:"
    static let videoPrefix = "ytv:"

    static func encode(artist: String, title: String) -> String {
        prefix + Data("\(artist)\t\(title)".utf8).base64EncodedString()
    }

    static func decode(_ id: String) -> (artist: String, title: String)? {
        guard id.hasPrefix(prefix),
              let data = Data(base64Encoded: String(id.dropFirst(prefix.count))),
              let raw = String(data: data, encoding: .utf8) else { return nil }
        let parts = raw.components(separatedBy: "\t")
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    static func encodeVideo(_ videoId: String) -> String { videoPrefix + videoId }
    static func decodeVideo(_ id: String) -> String? {
        id.hasPrefix(videoPrefix) ? String(id.dropFirst(videoPrefix.count)) : nil
    }
}

enum YouTubeMeta {
    static func clean(title rawTitle: String, channel: String) -> (artist: String, title: String) {
        var t = rawTitle
        let junk = #"(?i)\s*[\(\[][^\)\]]*(official|lyric|audio|video|visuali[sz]er|m/?v|hd|4k|remaster|explicit|color coded|performance)[^\)\]]*[\)\]]"#
        t = t.replacingOccurrences(of: junk, with: "", options: .regularExpression)
        if let bar = t.firstIndex(of: "|") { t = String(t[..<bar]) }

        var artist = cleanChannel(channel)
        for sep in [" - ", " – ", " — "] {
            if let r = t.range(of: sep) {
                artist = trim(String(t[..<r.lowerBound]))
                t = String(t[r.upperBound...])
                break
            }
        }
        return (trim(artist), trim(t))
    }

    private static func cleanChannel(_ c: String) -> String {
        var s = c.replacingOccurrences(of: " - Topic", with: "")
        s = s.replacingOccurrences(of: #"(?i)\s*vevo\b"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\s*official\b"#, with: "", options: .regularExpression)
        return trim(s)
    }

    private static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: " \t-–—·"))
    }
}

final class YouTubeResolver {
    static let shared = YouTubeResolver()

    func resolve(artist: String, title: String) async -> ResolvedAudio? {
        let query = "\(artist) \(title)".trimmingCharacters(in: .whitespaces)
        guard let videoId = await searchVideoId(query) else { return nil }
        return await resolveVideo(id: videoId, title: title)
    }

    func resolveVideo(id videoId: String, title: String = "") async -> ResolvedAudio? {
        #if canImport(YouTubeKit)
        do {
            let audio = try await YouTube(videoID: videoId).streams.filterAudioOnly()
            let native = audio.filter { $0.isNativelyPlayable }
            let pool = native.isEmpty ? audio : native
            guard let stream = pool.max(by: {
                ($0.averageBitrate ?? $0.bitrate ?? 0) < ($1.averageBitrate ?? $1.bitrate ?? 0)
            }) else { return nil }
            return ResolvedAudio(url: stream.url, title: title)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    func search(_ query: String, limit: Int = 25) async -> [YouTubeResult] {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.youtube.com/results?search_query=\(q)&sp=EgIQAQ%253D%253D") else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return [] }

        var seen = Set<String>()
        var out: [YouTubeResult] = []
        for chunk in html.components(separatedBy: "\"videoRenderer\":{").dropFirst() {
            guard out.count < limit,
                  let vid = Self.firstGroup(chunk, #""videoId":"([\w-]{11})""#), !seen.contains(vid),
                  let title = Self.firstGroup(chunk, #""title":\{"runs":\[\{"text":"((?:[^"\\]|\\.)*)""#)
            else { continue }
            let author = Self.firstGroup(chunk, #""ownerText":\{"runs":\[\{"text":"((?:[^"\\]|\\.)*)""#)
                ?? Self.firstGroup(chunk, #""longBylineText":\{"runs":\[\{"text":"((?:[^"\\]|\\.)*)""#)
                ?? ""
            seen.insert(vid)
            out.append(YouTubeResult(videoId: vid, title: Self.unescapeJSON(title), author: Self.unescapeJSON(author)))
        }
        return out
    }

    private static func firstGroup(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func unescapeJSON(_ raw: String) -> String {
        (try? JSONDecoder().decode(String.self, from: Data("\"\(raw)\"".utf8))) ?? raw
    }

    private func searchVideoId(_ query: String) async -> String? {
        guard let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.youtube.com/results?search_query=\(q)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8),
              let range = html.range(of: "\"videoId\":\"") else { return nil }
        let id = String(html[range.upperBound...].prefix(11))
        return id.count == 11 ? id : nil
    }
}

extension DisplayableSong {
    static func youtubeVideo(videoId: String, rawTitle: String, channel: String) -> DisplayableSong {
        let (artist, title) = YouTubeMeta.clean(title: rawTitle, channel: channel)
        return DisplayableSong(
            id: YouTubeID.encodeVideo(videoId),
            title: title, artist: artist, albumId: nil, albumName: nil, artistId: nil,
            genre: nil, duration: 0, trackNumber: nil, isDownloaded: false,
            coverArtId: "ytimg:\(videoId)",
            audioFormat: "YouTube", replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil, replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    static func youtube(artist: String, title: String) -> DisplayableSong {
        DisplayableSong(
            id: YouTubeID.encode(artist: artist, title: title),
            title: title,
            artist: artist,
            albumId: nil,
            albumName: nil,
            artistId: nil,
            genre: nil,
            duration: 0,
            trackNumber: nil,
            isDownloaded: false,
            coverArtId: nil,
            audioFormat: "YouTube",
            replayGainTrackGain: nil,
            replayGainTrackPeak: nil,
            replayGainAlbumGain: nil,
            replayGainAlbumPeak: nil,
            replayGainBaseGain: nil,
            replayGainFallbackGain: nil
        )
    }
}
