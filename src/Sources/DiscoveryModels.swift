import Foundation

enum DiscoverySource: String, Codable {
    case lastfm
    case listenbrainz

    var displayName: String { self == .lastfm ? "Last.fm" : "ListenBrainz" }
}

/// "discover" = service-generated charts/recommendations; "recovered" = the
/// user's own playlists pulled back from the service. Shown in separate groups.
enum DiscoveryKind: String, Codable {
    case discover
    case recovered
}

/// A single track inside a discovery playlist. Starts as a placeholder; download
/// state is derived from `OfflineDownloadManager` (matched by `id`).
struct DiscoveryTrack: Codable, Identifiable, Hashable {
    let id: String          // "${source}:${artist}-${title}"
    let title: String
    let artist: String
    var album: String?
    var mbid: String?
    var coverURL: String?
    var durationSec: Int?
}

/// One source chart/playlist surfaced as its own dedicated app playlist.
struct DiscoveryPlaylist: Codable, Identifiable, Hashable {
    let id: String          // "${source}:${sourceId}"
    let source: DiscoverySource
    var kind: DiscoveryKind = .discover
    let sourceId: String
    let name: String
    var description: String?
    var coverURL: String?
    var tracks: [DiscoveryTrack] = []
}

func discoveryTrackId(_ source: DiscoverySource, _ artist: String, _ title: String) -> String {
    func slug(_ s: String) -> String {
        let lowered = s.lowercased()
        let mapped = lowered.map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : "-"
        }
        return String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }
    return "\(source.rawValue):\(slug(artist))-\(slug(title))"
}
