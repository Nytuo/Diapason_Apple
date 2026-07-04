// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import Foundation
import SwiftSonic
import OSLog

/// Single entry point for obtaining a playable URL for a given song.
/// Resolution order: downloaded → cached → stream.
/// PlayerService always calls this — it never contacts SwiftSonic directly.
actor MediaResolver: MediaResolverProtocol {
    private let downloadService: any DownloadServiceProtocol
    private let cacheService: any CacheServiceProtocol
    private let serverService: any ServerServiceProtocol
    private let serverState: ServerState
    // Diapason: the library router — used to resolve stream URLs for Plex/Local backends,
    // which don't go through the SwiftSonic client.
    private let libraryService: any LibraryServiceProtocol

    init(
        downloadService: any DownloadServiceProtocol,
        cacheService: any CacheServiceProtocol,
        serverService: any ServerServiceProtocol,
        serverState: ServerState,
        libraryService: any LibraryServiceProtocol
    ) {
        self.downloadService = downloadService
        self.cacheService = cacheService
        self.serverService = serverService
        self.serverState = serverState
        self.libraryService = libraryService
    }

    func resolve(songId: String, serverId: UUID) async throws -> MediaSource {
        // 1. Permanent download — always preferred, works offline.
        if let url = await downloadService.downloadedURL(forSongId: songId, serverId: serverId) {
            Logger.resolver.debug("Resolved '\(songId, privacy: .public)' from permanent download.")
            return .downloaded(url)
        }

        // 2. Ephemeral cache — no network needed, bump LRU clock.
        if let url = await cacheService.cachedURL(forSongId: songId, serverId: serverId) {
            await cacheService.touch(songId: songId, serverId: serverId)
            Logger.resolver.debug("Resolved '\(songId, privacy: .public)' from cache.")
            return .cached(url)
        }

        // Diapason: YouTube-backed songs downloaded for offline playback → local file.
        if songId.hasPrefix(YouTubeID.videoPrefix) || songId.hasPrefix(YouTubeID.prefix) {
            if let local = await MainActor.run(body: { YouTubeDownloadManager.shared.localURL(forSongId: songId) }) {
                Logger.resolver.debug("Resolved '\(songId, privacy: .public)' from YouTube download.")
                return .downloaded(local)
            }
        }

        // Diapason: YouTube-backed virtual songs (recommendations / YouTube search).
        if songId.hasPrefix(YouTubeID.videoPrefix) {
            let isOnline = await MainActor.run { serverState.isOnline }
            guard isOnline else { throw CassetteError.offlineUnavailable(songId: songId) }
            guard let videoId = YouTubeID.decodeVideo(songId),
                  let audio = await YouTubeResolver.shared.resolveVideo(id: videoId) else {
                throw CassetteError.mediaNotFound(songId: songId)
            }
            Logger.resolver.debug("Resolved '\(songId, privacy: .public)' via YouTube video.")
            return .stream(audio.url, customHeaders: [:])
        }
        if songId.hasPrefix(YouTubeID.prefix) {
            let isOnline = await MainActor.run { serverState.isOnline }
            guard isOnline else { throw CassetteError.offlineUnavailable(songId: songId) }
            guard let (artist, title) = YouTubeID.decode(songId),
                  let audio = await YouTubeResolver.shared.resolve(artist: artist, title: title) else {
                throw CassetteError.mediaNotFound(songId: songId)
            }
            Logger.resolver.debug("Resolved '\(songId, privacy: .public)' via YouTube.")
            return .stream(audio.url, customHeaders: [:])
        }

        // Diapason: non-Subsonic backends resolve their own stream URL via the router.
        let backendKind = await MainActor.run { serverState.activeServer?.backendKind ?? "subsonic" }

        // Local files are always available offline — resolve before the online guard.
        if backendKind == "local" {
            guard let fileURL = await libraryService.streamURL(songId: songId) else {
                throw CassetteError.mediaNotFound(songId: songId)
            }
            Logger.resolver.debug("Resolved '\(songId, privacy: .public)' as local file.")
            return .downloaded(fileURL)
        }

        // 3. Offline guard — no local copy available, device has no connectivity.
        let isOnline = await MainActor.run { serverState.isOnline }
        guard isOnline else {
            Logger.resolver.warning("'\(songId, privacy: .public)' not available offline.")
            throw CassetteError.offlineUnavailable(songId: songId)
        }

        // Plex: the router builds a tokened stream URL (no extra auth headers needed).
        if backendKind == "plex" {
            guard let streamURL = await libraryService.streamURL(songId: songId) else {
                throw CassetteError.mediaNotFound(songId: songId)
            }
            Logger.resolver.debug("Resolved '\(songId, privacy: .public)' as Plex stream.")
            return .stream(streamURL, customHeaders: [:])
        }

        // 4. Subsonic stream. Custom headers injected so AVPlayer reaches Cloudflare-protected hosts.
        // AVURLAssetHTTPHeaderFieldsKey is used at the PlayerService call site.
        // TODO(v1.x): trigger background cache write alongside the stream.
        let client = try await serverService.makeSwiftSonicClient()
        guard let streamURL = client.streamURL(id: songId) else {
            throw CassetteError.mediaNotFound(songId: songId)
        }
        let creds = try await serverService.activeCredentials()
        Logger.resolver.debug("Resolved '\(songId, privacy: .public)' as stream.")
        return .stream(streamURL, customHeaders: creds.customHeaders)
    }

    func resolveRadio(_ station: InternetRadioStation) async throws -> MediaSource {
        guard let url = URL(string: station.streamUrl) else {
            Logger.resolver.error("Invalid stream URL for radio station '\(station.id, privacy: .public)': \(station.streamUrl, privacy: .private)")
            throw CassetteError.mediaNotFound(songId: station.id)
        }

        let isOnline = await MainActor.run { serverState.isOnline }
        guard isOnline else {
            Logger.resolver.warning("Radio '\(station.id, privacy: .public)' not available offline.")
            throw CassetteError.offlineUnavailable(songId: station.id)
        }

        let creds = try await serverService.activeCredentials()
        Logger.resolver.debug("Resolved radio '\(station.id, privacy: .public)' as live stream.")
        return .liveStream(url, customHeaders: creds.customHeaders, stationId: station.id)
    }
}
