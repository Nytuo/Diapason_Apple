import Foundation
import SwiftUI

// MARK: - Lyric Line

struct LyricLine: Identifiable {
    let id: Int
    let startMs: Int?   // nil = unsynced
    let text: String
}

// MARK: - Protocols

protocol MusicBackend: ObservableObject {
    var isConnected: Bool { get }
    func ping() async throws -> Bool
    
    // Library
    func getAlbums() async throws -> [Album]
    func getAlbumDetails(id: String) async throws -> AlbumDetail
    func getArtists() async throws -> [Artist]
    func getArtistDetails(id: String) async throws -> ArtistDetail
    func getPlaylists() async throws -> [Playlist]
    func getPlaylistDetails(id: String) async throws -> PlaylistDetail
    func createPlaylist(name: String, songId: String?) async throws
    func addSongToPlaylist(songId: String, playlistId: String) async throws
    
    // Features
    func search(query: String) async throws -> [Song]
    func getLyrics(id: String) async throws -> String?
    func getLyricLines(id: String) async throws -> [LyricLine]?

    // Favorites / star
    func getStarredSongs() async throws -> [Song]
    func setStarred(id: String, starred: Bool) async
    func isStarred(id: String) async -> Bool
    
    // Discover
    func getRecentlyAddedAlbums() async throws -> [Album]
    func getMostPlayedAlbums() async throws -> [Album]
    func getRandomAlbums() async throws -> [Album]
    
    // Media
    func getCoverArtURL(id: String) -> URL?
    func getStreamURL(id: String) -> URL?
    
    // Progress
    func updateProgress(id: String, ratingKey: String?, state: String, time: Double, duration: Double) async
}

// Default no-op implementations so backends without favorites support (e.g. Plex) compile.
extension MusicBackend {
    func getStarredSongs() async throws -> [Song] { [] }
    func setStarred(id: String, starred: Bool) async {}
    func isStarred(id: String) async -> Bool { false }
}

// MARK: - Shared Models

struct Album: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let title: String?
    let artist: String
    let artistId: String?
    let coverArt: String?
    let year: Int?
    
    var displayTitle: String { title ?? name ?? "Unknown Album" }
}

struct AlbumDetail: Codable, Identifiable {
    let id: String
    let name: String
    let artist: String
    let song: [Song]
}

struct Artist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let albumCount: Int?
    let coverArt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, albumCount
        case coverArt = "coverArt"
        case artistImageUrl = "artistImageUrl"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        albumCount = try container.decodeIfPresent(Int.self, forKey: .albumCount)
        coverArt = try container.decodeIfPresent(String.self, forKey: .coverArt) ?? container.decodeIfPresent(String.self, forKey: .artistImageUrl)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(albumCount, forKey: .albumCount)
        try container.encodeIfPresent(coverArt, forKey: .coverArt)
    }
    
    // Memberwise initializer for manual creation (like in PlexClient)
    init(id: String, name: String, albumCount: Int?, coverArt: String?) {
        self.id = id
        self.name = name
        self.albumCount = albumCount
        self.coverArt = coverArt
    }
}

struct ArtistDetail: Codable, Identifiable {
    let id: String
    let name: String
    let biography: String?
    let album: [Album]
}

struct Playlist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let owner: String?
    let songCount: Int?
    let coverArt: String?
}

struct PlaylistDetail: Codable, Identifiable {
    let id: String
    let name: String
    let song: [Song]
}

struct Song: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let artistId: String?
    let album: String
    let albumId: String
    let duration: Int?
    let track: Int?
    let coverArt: String?
    let ratingKey: String?
    let bitRate: Int?

    /// Human-readable quality string, e.g. "320 kbps" or "Lossless"
    var qualityLabel: String? {
        if id.hasPrefix("local_song_") { return "Local" }
        if let br = bitRate {
            if br >= 1000 { return "Lossless" }
            return "\(br) kbps"
        }
        return nil
    }
}

// MARK: - Subsonic API Types

struct SubsonicResponse<T: Decodable>: Decodable {
    let subsonicResponse: SubsonicInnerResponse<T>
    enum CodingKeys: String, CodingKey { case subsonicResponse = "subsonic-response" }
}

struct SubsonicInnerResponse<T: Decodable>: Decodable {
    let status: String
    let version: String
    let albumList2: T?
    let album: T?
    let artists: T?
    let artist: T?
    let searchResult3: T?
    let playlists: T?
    let playlist: T?
    let lyrics: T?
    let lyricsList: T?
    let starred2: T?
}

struct StarredContainer: Decodable { let song: [Song]? }

struct SubsonicPlaylistsContainer: Decodable { let playlist: [SubsonicPlaylist] }
struct SubsonicPlaylist: Decodable {
    let id: String
    let name: String
    let owner: String?
    let songCount: Int?
    let coverArt: String?
    func toPlaylist() -> Playlist {
        Playlist(id: id, name: name, owner: owner, songCount: songCount, coverArt: coverArt)
    }
}

struct SubsonicPlaylistDetailContainer: Decodable {
    let id: String
    let name: String
    let entry: [Song]?
}

struct SubsonicLyrics: Decodable {
    let value: String?
}

// OpenSubsonic getLyricsBySongId models
struct OpenSubsonicLyricsContainer: Decodable {
    let structuredLyrics: [OpenSubsonicStructuredLyrics]
}
struct OpenSubsonicStructuredLyrics: Decodable {
    let lang: String?
    let synced: Bool?
    let line: [OpenSubsonicLyricLine]
}
struct OpenSubsonicLyricLine: Decodable {
    let value: String
    let start: Int?
}

// MARK: - Missing Containers for SubsonicClient

struct EmptyData: Decodable {}
struct AlbumListContainer: Decodable { let album: [Album] }
struct AlbumDetailContainer: Decodable { let song: [Song] }
struct ArtistListContainer: Decodable { let index: [ArtistIndex] }
struct ArtistIndex: Decodable { let artist: [Artist] }
struct ArtistDetailContainer: Decodable { let album: [Album] }
struct SearchResultContainer: Decodable { let song: [Song]? }

// MARK: - Color Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
        }
        }

        struct URLUtils {
        static func normalize(_ urlString: String, defaultPort: Int) -> String {
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return "" }

        let hasScheme = normalized.hasPrefix("http://") || normalized.hasPrefix("https://")
        let hostPart = hasScheme ? (normalized.components(separatedBy: "://").last ?? normalized) : normalized

        var finalURL = hasScheme ? normalized : "http://\(normalized)"

        // Add port if missing (check if hostPart contains a colon)
        if !hostPart.contains(":") {
            finalURL = finalURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + ":\(defaultPort)"
        }

        return finalURL
        }
        }

        import Foundation

struct LyricsResult: Codable {
    let provider: String
    let synced: String?
    let plain: String?
}

class LyricsManager {
    static let shared = LyricsManager()
    
    private let client = URLSession.shared
    private let fileManager = FileManager.default
    
    private var cacheURL: URL {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let url = paths[0].appendingPathComponent("lyrics_cache", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    private func getCacheKey(artist: String, title: String) -> String {
        let raw = "\(artist.lowercased())_\(title.lowercased())"
        return raw.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
    }
    
    func fetchLyrics(artist: String, title: String, album: String? = nil, duration: Double? = nil) async -> LyricsResult? {
        let cacheKey = getCacheKey(artist: artist, title: title)
        
        // 1. Check local cache first
        if let cached = loadFromCache(key: cacheKey) {
            return cached
        }
        
        // 2. Try get API
        if let result = await getLyrics(artist: artist, title: title, album: album, duration: duration) {
            saveToCache(key: cacheKey, result: result)
            return result
        }
        
        // 3. Try search API
        if let result = await searchLyrics(artist: artist, title: title) {
            saveToCache(key: cacheKey, result: result)
            return result
        }
        
        return nil
    }
    
    private func saveToCache(key: String, result: LyricsResult) {
        let url = cacheURL.appendingPathComponent("\(key).json")
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: url)
        }
    }
    
    private func loadFromCache(key: String) -> LyricsResult? {
        let url = cacheURL.appendingPathComponent("\(key).json")
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LyricsResult.self, from: data)
    }
    
    private func getLyrics(artist: String, title: String, album: String?, duration: Double?) async -> LyricsResult? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title)
        ]
        if let album = album { queryItems.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration = duration { queryItems.append(URLQueryItem(name: "duration", value: String(format: "%.0f", duration))) }
        components.queryItems = queryItems
        
        guard let url = components.url else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Diapason/0.1 (https://github.com/)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await client.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            
            let json = try JSONDecoder().decode(LRCLIBResult.self, from: data)
            if json.syncedLyrics != nil || json.plainLyrics != nil {
                return LyricsResult(provider: "LRCLIB", synced: json.syncedLyrics, plain: json.plainLyrics)
            }
        } catch {
            print("LRCLIB get error: \(error)")
        }
        return nil
    }
    
    private func searchLyrics(artist: String, title: String) async -> LyricsResult? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title)
        ]
        
        guard let url = components.url else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Diapason/0.1 (https://github.com/)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await client.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            
            let results = try JSONDecoder().decode([LRCLIBResult].self, from: data)
            if let first = results.first {
                if first.syncedLyrics != nil || first.plainLyrics != nil {
                    return LyricsResult(provider: "LRCLIB", synced: first.syncedLyrics, plain: first.plainLyrics)
                }
            }
        } catch {
            print("LRCLIB search error: \(error)")
        }
        return nil
    }
    
    func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = "\\[(\\d+):(\\d+)\\.(\\d+)\\](.*)"
        let regex = try? NSRegularExpression(pattern: pattern)
        
        let nsString = lrc as NSString
        let matches = regex?.matches(in: lrc, range: NSRange(location: 0, length: nsString.length)) ?? []
        
        for (index, match) in matches.enumerated() {
            let min = Int(nsString.substring(with: match.range(at: 1))) ?? 0
            let sec = Int(nsString.substring(with: match.range(at: 2))) ?? 0
            let msPart = Int(nsString.substring(with: match.range(at: 3))) ?? 0
            let text = nsString.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
            
            // Adjust msPart: if it's 2 digits (e.g. .45), it's 450ms. If 3, it's ms.
            let msMultiplier = match.range(at: 3).length == 2 ? 10 : 1
            let totalMs = (min * 60 + sec) * 1000 + msPart * msMultiplier
            
            lines.append(LyricLine(id: index, startMs: totalMs, text: text))
        }
        
        // If regex didn't find anything, try splitting by newlines for plain text
        if lines.isEmpty {
            return lrc.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .enumerated()
                .map { LyricLine(id: $0, startMs: nil, text: $1) }
        }
        
        return lines
    }
}

struct LRCLIBResult: Codable {
    let plainLyrics: String?
    let syncedLyrics: String?
}
