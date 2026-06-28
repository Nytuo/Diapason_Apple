import Foundation
import Combine

@MainActor
class UnifiedMusicClient: ObservableObject, MusicBackend {
    static let shared = UnifiedMusicClient()
    
    @Published var isConnected: Bool = true // Always connected because local library is always available
    
    private var cancellables = Set<AnyCancellable>()
    
    private var activeRemoteClient: any MusicBackend {
        switch BackendManager.shared.activeType {
        case .subsonic: return SubsonicClient.shared
        case .plex: return PlexClient.shared
        }
    }
    
    private init() {
        // Observe remote client connection status if needed, but local files are always ready
        BackendManager.shared.$activeType
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    func ping() async throws -> Bool {
        do {
            let res = try await activeRemoteClient.ping()
            return res
        } catch {
            return false
        }
    }
    
    func getAlbums() async throws -> [Album] {
        var list: [Album] = []
        
        // 1. Fetch remote albums (if remote client is connected)
        if activeRemoteClient.isConnected {
            if let remoteList = try? await activeRemoteClient.getAlbums() {
                list.append(contentsOf: remoteList)
            }
        }
        
        // 2. Fetch local albums
        list.append(contentsOf: LocalMusicManager.shared.albums)
        return list
    }
    
    func getAlbumDetails(id: String) async throws -> AlbumDetail {
        if id.hasPrefix("local_") {
            // Local album details
            let songs = LocalMusicManager.shared.songs.filter { $0.albumId == id }
            let albumName = LocalMusicManager.shared.albums.first(where: { $0.id == id })?.displayTitle ?? "Unknown Album"
            let artistName = LocalMusicManager.shared.albums.first(where: { $0.id == id })?.artist ?? "Unknown Artist"
            return AlbumDetail(id: id, name: albumName, artist: artistName, song: songs)
        } else {
            return try await activeRemoteClient.getAlbumDetails(id: id)
        }
    }
    
    func getArtists() async throws -> [Artist] {
        var list: [Artist] = []
        if activeRemoteClient.isConnected {
            if let remoteList = try? await activeRemoteClient.getArtists() {
                list.append(contentsOf: remoteList)
            }
        }
        list.append(contentsOf: LocalMusicManager.shared.artists)
        return list
    }
    
    func getArtistDetails(id: String) async throws -> ArtistDetail {
        if id.hasPrefix("local_") {
            let artist = LocalMusicManager.shared.artists.first(where: { $0.id == id })
            let name = artist?.name ?? "Unknown Artist"
            let albums = LocalMusicManager.shared.albums.filter { $0.artistId == id }
            return ArtistDetail(id: id, name: name, biography: nil, album: albums)
        } else {
            return try await activeRemoteClient.getArtistDetails(id: id)
        }
    }
    
    func getPlaylists() async throws -> [Playlist] {
        var list: [Playlist] = []
        if activeRemoteClient.isConnected {
            if let remoteList = try? await activeRemoteClient.getPlaylists() {
                list.append(contentsOf: remoteList)
            }
        }
        // Local files don't support custom playlists yet, but we could add them if needed.
        return list
    }
    
    func getPlaylistDetails(id: String) async throws -> PlaylistDetail {
        return try await activeRemoteClient.getPlaylistDetails(id: id)
    }
    
    func createPlaylist(name: String, songId: String?) async throws {
        try await activeRemoteClient.createPlaylist(name: name, songId: songId)
    }
    
    func addSongToPlaylist(songId: String, playlistId: String) async throws {
        try await activeRemoteClient.addSongToPlaylist(songId: songId, playlistId: playlistId)
    }
    
    func search(query: String) async throws -> [Song] {
        var results: [Song] = []
        if activeRemoteClient.isConnected {
            if let remoteResults = try? await activeRemoteClient.search(query: query) {
                results.append(contentsOf: remoteResults)
            }
        }
        let localResults = LocalMusicManager.shared.songs.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.artist.localizedCaseInsensitiveContains(query) ||
            $0.album.localizedCaseInsensitiveContains(query)
        }
        results.append(contentsOf: localResults)
        return results
    }
    
    func getLyrics(id: String) async throws -> String? {
        if id.hasPrefix("local_") {
            guard let song = LocalMusicManager.shared.songs.first(where: { $0.id == id }) else { return nil }
            if let res = await LyricsManager.shared.fetchLyrics(artist: song.artist, title: song.title, album: song.album) {
                return res.plain ?? res.synced
            }
            return nil
        }
        return try await activeRemoteClient.getLyrics(id: id)
    }
    
    func getLyricLines(id: String) async throws -> [LyricLine]? {
        if id.hasPrefix("local_") {
            guard let song = LocalMusicManager.shared.songs.first(where: { $0.id == id }) else { return nil }
            if let res = await LyricsManager.shared.fetchLyrics(artist: song.artist, title: song.title, album: song.album) {
                let parsed = LyricsManager.shared.parseLRC(res.synced ?? res.plain ?? "")
                return parsed
            }
            return nil
        }
        return try await activeRemoteClient.getLyricLines(id: id)
    }
    
    func getStarredSongs() async throws -> [Song] {
        guard activeRemoteClient.isConnected else { return [] }
        return (try? await activeRemoteClient.getStarredSongs()) ?? []
    }

    func setStarred(id: String, starred: Bool) async {
        guard !id.hasPrefix("local_") else { return }
        await activeRemoteClient.setStarred(id: id, starred: starred)
    }

    func isStarred(id: String) async -> Bool {
        guard !id.hasPrefix("local_") else { return false }
        return await activeRemoteClient.isStarred(id: id)
    }

    func getRecentlyAddedAlbums() async throws -> [Album] {
        var list: [Album] = []
        if activeRemoteClient.isConnected {
            if let remoteList = try? await activeRemoteClient.getRecentlyAddedAlbums() {
                list.append(contentsOf: remoteList)
            }
        }
        list.append(contentsOf: LocalMusicManager.shared.albums.suffix(20))
        return list
    }
    
    func getMostPlayedAlbums() async throws -> [Album] {
        var list: [Album] = []
        if activeRemoteClient.isConnected {
            if let remoteList = try? await activeRemoteClient.getMostPlayedAlbums() {
                list.append(contentsOf: remoteList)
            }
        }
        list.append(contentsOf: LocalMusicManager.shared.albums.suffix(20))
        return list
    }
    
    func getRandomAlbums() async throws -> [Album] {
        var list: [Album] = []
        if activeRemoteClient.isConnected {
            if let remoteList = try? await activeRemoteClient.getRandomAlbums() {
                list.append(contentsOf: remoteList)
            }
        }
        list.append(contentsOf: LocalMusicManager.shared.albums.shuffled().prefix(20))
        return list
    }
    
    func getCoverArtURL(id: String) -> URL? {
        if id.hasPrefix("local_alb_") || id.hasPrefix("local_art_") {
            let coversDir = LocalMusicManager.shared.coversDirURL
            let fileURL = coversDir.appendingPathComponent("\(id).jpg")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
            return nil
        }
        
        if let offlineCover = OfflineDownloadManager.shared.getDownloadedCoverArtURL(forAlbumId: id) {
            return offlineCover
        }
        
        return activeRemoteClient.getCoverArtURL(id: id)
    }
    
    func getStreamURL(id: String) -> URL? {
        if id.hasPrefix("local_song_") {
            return LocalMusicManager.shared.getStreamURL(id: id)
        }
        return activeRemoteClient.getStreamURL(id: id)
    }
    
    func updateProgress(id: String, ratingKey: String?, state: String, time: Double, duration: Double) async {
        if id.hasPrefix("local_") {
            // Local playback has no server to report timeline progress to
            return
        }
        await activeRemoteClient.updateProgress(id: id, ratingKey: ratingKey, state: state, time: time, duration: duration)
    }
}
