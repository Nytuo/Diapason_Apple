import Foundation
import CryptoKit

class SubsonicClient: MusicBackend {
    @Published var serverURL: String = UserDefaults.standard.string(forKey: "subsonic_serverURL") ?? ""
    @Published var username: String = UserDefaults.standard.string(forKey: "subsonic_username") ?? ""
    @Published var password: String = UserDefaults.standard.string(forKey: "subsonic_password") ?? ""
    @Published var isConnected: Bool = false

    static let shared = SubsonicClient()

    func saveCredentials() {
        serverURL = URLUtils.normalize(serverURL, defaultPort: 4533)
        UserDefaults.standard.set(serverURL, forKey: "subsonic_serverURL")
        UserDefaults.standard.set(username, forKey: "subsonic_username")
        UserDefaults.standard.set(password, forKey: "subsonic_password")
    }

    private var authParams: String {
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let token = MD5(password + salt)
        return "u=\(username)&t=\(token)&s=\(salt)&v=1.16.1&c=diapason&f=json"
    }

    private func MD5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: string.data(using: .utf8) ?? Data())
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    func buildURL(endpoint: String, params: [String: String] = [:]) -> URL? {
        guard !serverURL.isEmpty else { return nil }
        var urlString = "\(serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/rest/\(endpoint).view?\(authParams)"
        for (key, value) in params {
            if let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlString += "&\(key)=\(encoded)"
            }
        }
        return URL(string: urlString)
    }

    func ping() async throws -> Bool {
        guard let url = buildURL(endpoint: "ping") else { return false }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<EmptyData>.self, from: data)
        let success = response.subsonicResponse.status == "ok"
        DispatchQueue.main.async { self.isConnected = success }
        return success
    }

    func getAlbums() async throws -> [Album] {
        guard let url = buildURL(endpoint: "getAlbumList2", params: ["type": "alphabeticalByArtist", "size": "500"]) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<AlbumListContainer>.self, from: data)
        return response.subsonicResponse.albumList2?.album ?? []
    }

    func getRecentlyAddedAlbums() async throws -> [Album] {
        guard let url = buildURL(endpoint: "getAlbumList2", params: ["type": "newest", "size": "50"]) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<AlbumListContainer>.self, from: data)
        return response.subsonicResponse.albumList2?.album ?? []
    }

    func getMostPlayedAlbums() async throws -> [Album] {
        guard let url = buildURL(endpoint: "getAlbumList2", params: ["type": "frequent", "size": "50"]) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<AlbumListContainer>.self, from: data)
        return response.subsonicResponse.albumList2?.album ?? []
    }

    func getRandomAlbums() async throws -> [Album] {
        guard let url = buildURL(endpoint: "getAlbumList2", params: ["type": "random", "size": "50"]) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<AlbumListContainer>.self, from: data)
        return response.subsonicResponse.albumList2?.album ?? []
    }

    func getAlbumDetails(id: String) async throws -> AlbumDetail {
        guard let url = buildURL(endpoint: "getAlbum", params: ["id": id]) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<SubsonicAlbumDetail>.self, from: data)
        guard let albumData = response.subsonicResponse.album else { throw URLError(.cannotParseResponse) }
        return AlbumDetail(id: albumData.id, name: albumData.name, artist: albumData.artist, song: albumData.song)
    }

    func getArtists() async throws -> [Artist] {
        guard let url = buildURL(endpoint: "getArtists") else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<ArtistListContainer>.self, from: data)
        return response.subsonicResponse.artists?.index.flatMap { $0.artist } ?? []
    }

    func getArtistDetails(id: String) async throws -> ArtistDetail {
        guard let url = buildURL(endpoint: "getArtist", params: ["id": id]) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<SubsonicArtistInner>.self, from: data)
        guard let artist = response.subsonicResponse.artist else { throw URLError(.cannotParseResponse) }
        return ArtistDetail(id: artist.id, name: artist.name, biography: artist.biography, album: artist.album ?? [])
    }

    func getPlaylists() async throws -> [Playlist] {
        guard let url = buildURL(endpoint: "getPlaylists") else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<SubsonicPlaylistsContainer>.self, from: data)
        return response.subsonicResponse.playlists?.playlist.map { $0.toPlaylist() } ?? []
    }

    func getPlaylistDetails(id: String) async throws -> PlaylistDetail {
        guard let url = buildURL(endpoint: "getPlaylist", params: ["id": id]) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<SubsonicPlaylistDetailContainer>.self, from: data)
        guard let pl = response.subsonicResponse.playlist else { throw URLError(.cannotParseResponse) }
        return PlaylistDetail(id: pl.id, name: pl.name, song: pl.entry ?? [])
    }

    func createPlaylist(name: String, songId: String?) async throws {
        var params = ["name": name]
        if let id = songId { params["songId"] = id }
        guard let url = buildURL(endpoint: "createPlaylist", params: params) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<EmptyData>.self, from: data)
        if response.subsonicResponse.status != "ok" {
            throw URLError(.badServerResponse)
        }
    }

    func addSongToPlaylist(songId: String, playlistId: String) async throws {
        guard let url = buildURL(endpoint: "updatePlaylist", params: ["playlistId": playlistId, "songIdToAdd": songId]) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<EmptyData>.self, from: data)
        if response.subsonicResponse.status != "ok" {
            throw URLError(.badServerResponse)
        }
    }

    func search(query: String) async throws -> [Song] {
        guard let url = buildURL(endpoint: "search3", params: ["query": query, "songCount": "50"]) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<SearchResultContainer>.self, from: data)
        return response.subsonicResponse.searchResult3?.song ?? []
    }

    func getLyricLines(id: String) async throws -> [LyricLine]? {
        // 1. Try OpenSubsonic getLyricsBySongId (returns timestamped lines)
        if let url = buildURL(endpoint: "getLyricsBySongId", params: ["id": id]),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let response = try? JSONDecoder().decode(SubsonicResponse<OpenSubsonicLyricsContainer>.self, from: data),
           let lines = response.subsonicResponse.lyricsList?.structuredLyrics.first?.line,
           !lines.isEmpty {
            return lines.enumerated().map { i, l in LyricLine(id: i, startMs: l.start, text: l.value) }
        }
        // 2. Fall back to plain getLyrics → split into unsynced lines
        if let plain = try? await getLyrics(id: id), !plain.isEmpty {
            return plain.components(separatedBy: "\n")
                .enumerated().map { i, t in LyricLine(id: i, startMs: nil, text: t) }
        }
        return nil
    }

    func getLyrics(id: String) async throws -> String? {
        // 1. Try OpenSubsonic extension: getLyricsBySongId
        if let url = buildURL(endpoint: "getLyricsBySongId", params: ["id": id]) {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let response = try? JSONDecoder().decode(SubsonicResponse<OpenSubsonicLyricsContainer>.self, from: data),
               let lines = response.subsonicResponse.lyricsList?.structuredLyrics.first?.line,
               !lines.isEmpty {
                return lines.map { $0.value }.joined(separator: "\n")
            }
        }
        // 2. Fall back to classic getLyrics (needs artist+title, not id)
        // We'll attempt with just the id param which some servers support
        guard let url = buildURL(endpoint: "getLyrics", params: ["id": id]) else { return nil }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<SubsonicLyrics>.self, from: data)
        let text = response.subsonicResponse.lyrics?.value
        return (text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? text : nil
    }

    // MARK: - Favorites (star)

    func getStarredSongs() async throws -> [Song] {
        guard let url = buildURL(endpoint: "getStarred2") else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SubsonicResponse<StarredContainer>.self, from: data)
        return response.subsonicResponse.starred2?.song ?? []
    }

    func setStarred(id: String, starred: Bool) async {
        guard let url = buildURL(endpoint: starred ? "star" : "unstar", params: ["id": id]) else { return }
        _ = try? await URLSession.shared.data(from: url)
    }

    func isStarred(id: String) async -> Bool {
        let starred = (try? await getStarredSongs()) ?? []
        return starred.contains { $0.id == id }
    }

    func getCoverArtURL(id: String) -> URL? {
        if id.starts(with: "http") { return URL(string: id) }
        return buildURL(endpoint: "getCoverArt", params: ["id": id, "size": "600"])
    }

    func getStreamURL(id: String) -> URL? {
        return buildURL(endpoint: "stream", params: ["id": id])
    }

    func updateProgress(id: String, ratingKey: String?, state: String, time: Double, duration: Double) async {
        // Report progress to Subsonic/Navidrome server (submission: false)
        guard let url = buildURL(endpoint: "scrobble", params: [
            "id": id,
            "submission": "false"
        ]) else { return }
        _ = try? await URLSession.shared.data(from: url)
    }
}

// Internal helpers for Subsonic JSON
struct SubsonicAlbumDetail: Decodable {
    let id: String
    let name: String
    let artist: String
    let song: [Song]
}

struct SubsonicArtistInner: Decodable {
    let id: String
    let name: String
    let biography: String?
    let album: [Album]?
}
