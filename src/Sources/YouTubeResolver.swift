import Foundation
#if canImport(YouTubeKit)
import YouTubeKit
#endif

struct ResolvedAudio {
    let url: URL
    let title: String
    let durationSec: Int
}

/// Resolves `(artist, title)` into a directly downloadable audio stream URL.
///
/// YouTubeKit handles stream extraction but has no search, so we first scrape a
/// video id from the results page, then hand it to YouTubeKit.
///
/// NOTE: add the YouTubeKit Swift package in Xcode
/// (https://github.com/alexeichhorn/YouTubeKit). Until then `resolve` returns
/// nil and downloads are gracefully skipped — the rest of the app still builds.
final class YouTubeResolver {
    static let shared = YouTubeResolver()

    func resolve(artist: String, title: String) async -> ResolvedAudio? {
        let query = "\(artist) \(title)".trimmingCharacters(in: .whitespaces)
        guard let videoId = await searchVideoId(query) else { return nil }
        #if canImport(YouTubeKit)
        do {
            let streams = try await YouTube(videoID: videoId).streams
            guard let stream = streams.filterAudioOnly().highestAudioBitrateStream()
                ?? streams.filterAudioOnly().first else { return nil }
            return ResolvedAudio(url: stream.url, title: title, durationSec: 0)
        } catch {
            print("YouTubeKit resolve failed: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Scrape the first `"videoId":"…"` (11 chars) from the YouTube results page.
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
