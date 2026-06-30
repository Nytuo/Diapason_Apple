import Foundation
import SwiftUI

/// Drives the music-discovery feature: fetches Last.fm / ListenBrainz playlists,
/// persists them, and downloads tracks on-device via `OfflineDownloadManager`.
/// Per-track download state is derived from the offline manager (matched by id).
@MainActor
final class DiscoveryFeedManager: ObservableObject {
    static let shared = DiscoveryFeedManager()

    @Published var playlists: [DiscoveryPlaylist] = []
    @Published var resolvingIds: Set<String> = []
    @Published var isLoading = false
    /// When set, the UI should open this Last.fm authorization URL.
    @Published var lastFmAuthURL: URL?
    @Published var lastFmAuthMessage: String?

    private let lb = ListenBrainzClient.shared
    private let lfm = LastFmClient.shared
    private let defaults = UserDefaults.standard
    private var lastFmAuthToken: String?

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("discovery.json")
    }

    init() { load() }

    // MARK: - Accounts (UserDefaults)

    var listenBrainzUser: String { defaults.string(forKey: "lb_user") ?? "" }
    var listenBrainzToken: String { defaults.string(forKey: "lb_token") ?? "" }
    var lastFmApiKey: String { defaults.string(forKey: "lfm_key") ?? "" }
    var lastFmApiSecret: String { defaults.string(forKey: "lfm_secret") ?? "" }
    var lastFmUser: String { defaults.string(forKey: "lfm_user") ?? "" }
    var lastFmSessionKey: String { defaults.string(forKey: "lfm_session") ?? "" }

    func saveListenBrainz(user: String, token: String) {
        defaults.set(user.trimmingCharacters(in: .whitespaces), forKey: "lb_user")
        defaults.set(token.trimmingCharacters(in: .whitespaces), forKey: "lb_token")
    }
    func saveLastFmCredentials(apiKey: String, apiSecret: String) {
        defaults.set(apiKey.trimmingCharacters(in: .whitespaces), forKey: "lfm_key")
        defaults.set(apiSecret.trimmingCharacters(in: .whitespaces), forKey: "lfm_secret")
    }
    func disconnectLastFm() {
        defaults.removeObject(forKey: "lfm_user")
        defaults.removeObject(forKey: "lfm_session")
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DiscoveryPlaylist].self, from: data) else { return }
        playlists = decoded
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(playlists) { try? data.write(to: fileURL) }
    }

    // MARK: - Feed

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        var out: [DiscoveryPlaylist] = []

        let lbUser = listenBrainzUser
        if !lbUser.isEmpty {
            out.append(DiscoveryPlaylist(id: "listenbrainz:top-recordings", source: .listenbrainz,
                sourceId: "top-recordings", name: "Your Top Recordings",
                description: "Your most-listened recordings on ListenBrainz"))
            let token = listenBrainzToken.isEmpty ? nil : listenBrainzToken
            out.append(contentsOf: await lb.createdForPlaylists(user: lbUser, token: token))
            out.append(contentsOf: await lb.userPlaylists(user: lbUser, token: token))
        }

        let key = lastFmApiKey
        if !key.isEmpty {
            out.append(DiscoveryPlaylist(id: "lastfm:chart-top", source: .lastfm, sourceId: "chart-top",
                name: "Last.fm Top Tracks", description: "Most-played tracks across Last.fm right now"))
            let user = lastFmUser
            if !user.isEmpty {
                out.append(DiscoveryPlaylist(id: "lastfm:user-top", source: .lastfm, sourceId: "user-top", name: "Your Top Tracks", description: "Your most-played tracks on Last.fm"))
                out.append(DiscoveryPlaylist(id: "lastfm:user-loved", source: .lastfm, sourceId: "user-loved", name: "Your Loved Tracks", description: "Tracks you've loved on Last.fm"))
                out.append(DiscoveryPlaylist(id: "lastfm:user-mix", source: .lastfm, sourceId: "user-mix", name: "Recommended for You", description: "Similar to your most-played track"))
            }
        }

        // Unique by id (a playlist can appear in both createdfor and user playlists).
        var seen = Set<String>()
        let unique = out.filter { seen.insert($0.id).inserted }
        // Preserve already-fetched tracks for playlists that still exist.
        let prev = Dictionary(uniqueKeysWithValues: playlists.map { ($0.id, $0.tracks) })
        playlists = unique.map { var p = $0; p.tracks = prev[$0.id] ?? []; return p }
        persist()
    }

    func loadTracks(playlistId: String, force: Bool = false) async {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        if !force, !playlists[idx].tracks.isEmpty { return }
        let playlist = playlists[idx]
        let tracks = await fetchTracks(playlist)
        if let i = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[i].tracks = tracks
            persist()
        }
    }

    private func fetchTracks(_ playlist: DiscoveryPlaylist) async -> [DiscoveryTrack] {
        switch playlist.source {
        case .lastfm:
            let key = lastFmApiKey
            guard !key.isEmpty else { return [] }
            let user = lastFmUser
            switch playlist.sourceId {
            case "chart-top": return await lfm.chartTopTracks(apiKey: key)
            case "user-top": return await lfm.userTopTracks(apiKey: key, user: user)
            case "user-loved": return await lfm.userLovedTracks(apiKey: key, user: user)
            case "user-mix": return await lfm.userMix(apiKey: key, user: user)
            default: return []
            }
        case .listenbrainz:
            let token = listenBrainzToken.isEmpty ? nil : listenBrainzToken
            if playlist.sourceId == "top-recordings" {
                let user = listenBrainzUser
                return user.isEmpty ? [] : await lb.topRecordings(user: user, token: token)
            }
            return await lb.playlistTracks(mbid: playlist.sourceId, token: token)
        }
    }

    // MARK: - Download

    func download(_ track: DiscoveryTrack) async {
        let offline = OfflineDownloadManager.shared
        if offline.isDownloaded(songId: track.id) || offline.isDownloading(songId: track.id) { return }
        resolvingIds.insert(track.id)
        let resolved = await YouTubeResolver.shared.resolve(artist: track.artist, title: track.title)
        resolvingIds.remove(track.id)
        guard let resolved else { return }
        offline.downloadSong(song: song(from: track, duration: resolved.durationSec), remoteURL: resolved.url)
    }

    func downloadAll(_ playlist: DiscoveryPlaylist) async {
        let offline = OfflineDownloadManager.shared
        for track in playlist.tracks where !offline.isDownloaded(songId: track.id) {
            await download(track)
        }
    }

    func downloadedSongs(in playlist: DiscoveryPlaylist) -> [Song] {
        playlist.tracks
            .filter { OfflineDownloadManager.shared.isDownloaded(songId: $0.id) }
            .map { song(from: $0, duration: $0.durationSec ?? 0) }
    }

    private func song(from t: DiscoveryTrack, duration: Int) -> Song {
        Song(id: t.id, title: t.title, artist: t.artist, artistId: nil,
             album: t.album ?? "Discover", albumId: "", duration: duration,
             track: nil, coverArt: t.coverURL, ratingKey: nil, bitRate: nil)
    }

    // MARK: - Last.fm auth

    func beginLastFmAuth() async {
        let key = lastFmApiKey, secret = lastFmApiSecret
        guard !key.isEmpty, !secret.isEmpty else {
            lastFmAuthMessage = "Enter your Last.fm API key and secret first."
            return
        }
        guard let token = await lfm.getAuthToken(apiKey: key, apiSecret: secret) else {
            lastFmAuthMessage = "Could not start Last.fm authorization."
            return
        }
        lastFmAuthToken = token
        lastFmAuthURL = lfm.authURL(apiKey: key, token: token)
    }

    func completeLastFmAuth() async {
        guard let token = lastFmAuthToken else { return }
        let key = lastFmApiKey, secret = lastFmApiSecret
        if let session = await lfm.getSession(apiKey: key, apiSecret: secret, token: token) {
            defaults.set(session.name, forKey: "lfm_user")
            defaults.set(session.key, forKey: "lfm_session")
            lastFmAuthMessage = "Connected as \(session.name)"
            lastFmAuthToken = nil
        } else {
            lastFmAuthMessage = "Not authorized yet — approve in the browser, then retry."
        }
    }
}
