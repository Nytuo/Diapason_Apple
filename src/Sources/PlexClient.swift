import Foundation

class PlexClient: MusicBackend {
    @Published var serverURL: String = UserDefaults.standard.string(forKey: "plex_serverURL") ?? ""
    @Published var token: String = UserDefaults.standard.string(forKey: "plex_token") ?? ""
    @Published var isConnected: Bool = false
    @Published var musicSectionId: String? = UserDefaults.standard.string(forKey: "plex_musicSectionId")

    static let shared = PlexClient()

    func saveCredentials() {
        serverURL = URLUtils.normalize(serverURL, defaultPort: 32400)
        UserDefaults.standard.set(serverURL, forKey: "plex_serverURL")
        UserDefaults.standard.set(token, forKey: "plex_token")
    }

    private func buildURL(path: String) -> URL? {
        guard !serverURL.isEmpty else { return nil }
        let separator = path.contains("?") ? "&" : "?"
        let urlString = "\(serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))\(path)\(separator)X-Plex-Token=\(token)"
        return URL(string: urlString)
    }

    private func getJSON<T: Decodable>(path: String) async throws -> T {
        guard let url = buildURL(path: path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func ping() async throws -> Bool {
        do {
            let container: PlexMediaContainer<SectionContainer> = try await getJSON(path: "/library/sections")
            let section = container.mediaContainer.directory.first { $0.type == "artist" || $0.type == "music" }
            if let section = section {
                DispatchQueue.main.async {
                    self.musicSectionId = section.key
                    self.isConnected = true
                    UserDefaults.standard.set(section.key, forKey: "plex_musicSectionId")
                }
                return true
            }
        } catch { print("Plex ping failed: \(error)") }
        DispatchQueue.main.async { self.isConnected = false }
        return false
    }

    func getAlbums() async throws -> [Album] {
        guard let section = musicSectionId else { return [] }
        let container: PlexMediaContainer<MetadataContainer> = try await getJSON(path: "/library/sections/\(section)/albums")
        return container.mediaContainer.metadata.map { $0.toAlbum() }
    }

    func getRecentlyAddedAlbums() async throws -> [Album] {
        guard let section = musicSectionId else { return [] }
        let container: PlexMediaContainer<MetadataContainer> = try await getJSON(path: "/library/sections/\(section)/albums?sort=addedAt:desc")
        return container.mediaContainer.metadata.map { $0.toAlbum() }
    }

    func getMostPlayedAlbums() async throws -> [Album] {
        guard let section = musicSectionId else { return [] }
        let container: PlexMediaContainer<MetadataContainer> = try await getJSON(path: "/library/sections/\(section)/albums?sort=viewCount:desc")
        return container.mediaContainer.metadata.map { $0.toAlbum() }
    }

    func getRandomAlbums() async throws -> [Album] {
        let all = try await getAlbums()
        return Array(all.shuffled().prefix(50))
    }

    func getAlbumDetails(id: String) async throws -> AlbumDetail {
        let container: PlexMediaContainer<MetadataContainer> = try await getJSON(path: "/library/metadata/\(id)/children")
        let albumContainer: PlexMediaContainer<MetadataContainer> = try await getJSON(path: "/library/metadata/\(id)")
        let albumMeta = albumContainer.mediaContainer.metadata.first!
        return AlbumDetail(id: id, name: albumMeta.title, artist: albumMeta.parentTitle ?? "Unknown Artist", song: container.mediaContainer.metadata.map { $0.toSong() })
    }

    func getArtists() async throws -> [Artist] {
        guard let section = musicSectionId else { return [] }
        let container: PlexMediaContainer<MetadataContainer> = try await getJSON(path: "/library/sections/\(section)/all")
        return container.mediaContainer.metadata.map { Artist(id: $0.ratingKey, name: $0.title, albumCount: nil, coverArt: $0.thumb) }
    }

    func getArtistDetails(id: String) async throws -> ArtistDetail {
        let container: PlexMediaContainer<MetadataContainer> = try await getJSON(path: "/library/metadata/\(id)/children")
        let artistContainer: PlexMediaContainer<MetadataContainer> = try await getJSON(path: "/library/metadata/\(id)")
        let artistMeta = artistContainer.mediaContainer.metadata.first!
        return ArtistDetail(id: id, name: artistMeta.title, biography: artistMeta.summary, album: container.mediaContainer.metadata.map { $0.toAlbum() })
    }

    func getPlaylists() async throws -> [Playlist] {
        let container: PlexMediaContainer<MetadataContainer> = try await getJSON(path: "/playlists")
        return container.mediaContainer.metadata.filter { $0.playlistType == "audio" }.map {
            Playlist(id: $0.ratingKey, name: $0.title, owner: nil, songCount: $0.leafCount, coverArt: $0.composite ?? $0.thumb)
        }
    }

    func getPlaylistDetails(id: String) async throws -> PlaylistDetail {
        let container: PlexMediaContainer<MetadataContainer> = try await getJSON(path: "/playlists/\(id)/items")
        let metaContainer: PlexMediaContainer<MetadataContainer> = try await getJSON(path: "/playlists/\(id)")
        let name = metaContainer.mediaContainer.metadata.first?.title ?? "Playlist"
        return PlaylistDetail(id: id, name: name, song: container.mediaContainer.metadata.map { $0.toSong() })
    }

    func createPlaylist(name: String, songId: String?) async throws {
        // Not implemented for Plex yet
    }

    func addSongToPlaylist(songId: String, playlistId: String) async throws {
        // Not implemented for Plex yet
    }

    func search(query: String) async throws -> [Song] {
        let path = "/library/all?type=10&query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        let container: PlexMediaContainer<MetadataContainer> = try await getJSON(path: path)
        return container.mediaContainer.metadata.map { $0.toSong() }
    }

    func getLyricLines(id: String) async throws -> [LyricLine]? { return nil }

    func getLyrics(id: String) async throws -> String? {
        // Plex lyrics are complex to fetch via REST and often require sidecar files or specialized streams.
        // Returning nil for now to keep it simple.
        return nil
    }

    func getCoverArtURL(id: String) -> URL? {
        if id.starts(with: "http") { return URL(string: id) }
        if id.starts(with: "/") { return buildURL(path: id) }
        return nil
    }

    func getStreamURL(id: String) -> URL? {
        if id.starts(with: "/") { return buildURL(path: id) }
        return nil
    }
    
    func updateProgress(id: String, ratingKey: String?, state: String, time: Double, duration: Double) async {
        guard let ratingKey = ratingKey else { return }
        let path = "/:/timeline?ratingKey=\(ratingKey)&state=\(state)&time=\(Int(time * 1000))&duration=\(Int(duration * 1000))"
        guard let url = buildURL(path: path) else { return }
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        _ = try? await URLSession.shared.data(for: request)
    }
}

// Plex JSON Mappings
struct PlexMediaContainer<T: Decodable>: Decodable {
    let mediaContainer: T
    enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" }
}

struct SectionContainer: Decodable {
    let directory: [PlexSection]
    enum CodingKeys: String, CodingKey { case directory = "Directory" }
}

struct PlexSection: Decodable {
    let key: String
    let type: String
}

struct MetadataContainer: Decodable {
    let metadata: [PlexMetadata]
    enum CodingKeys: String, CodingKey { case metadata = "Metadata" }
}

struct PlexMetadata: Decodable {
    let ratingKey: String
    let title: String
    let parentTitle: String?
    let grandparentTitle: String?
    let parentKey: String?
    let grandparentKey: String?
    let thumb: String?
    let composite: String?
    let year: Int?
    let index: Int?
    let parentIndex: Int?
    let duration: Int?
    let playlistType: String?
    let leafCount: Int?
    let summary: String?
    let media: [PlexMedia]?

    func toAlbum() -> Album {
        Album(id: ratingKey, name: title, title: title, artist: parentTitle ?? "Unknown Artist", artistId: parentKey?.replacingOccurrences(of: "/library/metadata/", with: ""), coverArt: thumb, year: year)
    }

    func toSong() -> Song {
        let partKey = media?.first?.part.first?.key ?? ""
        let br = media?.first?.bitrate
        return Song(id: partKey, title: title, artist: grandparentTitle ?? "Unknown Artist", artistId: grandparentKey?.replacingOccurrences(of: "/library/metadata/", with: ""), album: parentTitle ?? "Unknown Album", albumId: parentKey?.replacingOccurrences(of: "/library/metadata/", with: "") ?? "", duration: (duration ?? 0) / 1000, track: index, coverArt: thumb, ratingKey: ratingKey, bitRate: br)
    }
}

struct PlexMedia: Decodable {
    let bitrate: Int?
    let part: [PlexPart]
    enum CodingKeys: String, CodingKey { case bitrate, part = "Part" }
}

struct PlexPart: Decodable {
    let key: String
}
