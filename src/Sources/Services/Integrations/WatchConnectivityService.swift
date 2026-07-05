// Diapason — iPhone side of the Apple Watch companion remote.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.
//
// Pushes now-playing metadata (+ a small artwork thumbnail) to the paired watch
// via WCSession application context, and executes transport commands the watch
// sends back. The phone remains the audio source; the watch is a remote.

#if os(iOS)
import Foundation
import SwiftData
import WatchConnectivity
import UIKit
import OSLog

private let watchLog = Logger(subsystem: "fr.nytuo.Diapason", category: "watch-sync")

/// A downloaded playlist the user can pick to sync to the watch.
struct WatchSyncablePlaylist: Identifiable, Hashable {
    let id: String            // playlistId
    let name: String
    let coverArtId: String?
    let trackCount: Int
}

@MainActor
final class WatchConnectivityService: NSObject, ObservableObject {
    private weak var playerState: PlayerState?
    private weak var playerService: (any PlayerServiceProtocol)?
    private var artworkCache: ArtworkImageCache?
    private var downloadService: (any DownloadServiceProtocol)?
    private var modelContainer: ModelContainer?
    private var lastArtworkId: String?
    private var lastArtworkData: Data?

    /// Progress of an on-device sync of downloaded tracks to the watch.
    @Published var isSyncing = false
    @Published var syncedCount = 0
    @Published var totalToSync = 0
    /// Human-readable last-sync status, shown in the picker so failures aren't silent.
    @Published var status = ""

    /// Why a sync can't proceed, or nil if it can.
    private func blockingReason() -> String? {
        guard WCSession.isSupported() else { return "This device doesn't support Apple Watch." }
        let s = WCSession.default
        guard s.activationState == .activated else { return "Watch session not ready — reopen the app." }
        guard s.isPaired else { return "No Apple Watch is paired with this iPhone." }
        guard s.isWatchAppInstalled else { return "Install the Diapason app on your Apple Watch first." }
        return nil
    }

    func start(playerState: PlayerState,
               playerService: any PlayerServiceProtocol,
               artworkCache: ArtworkImageCache,
               downloadService: any DownloadServiceProtocol,
               modelContainer: ModelContainer) {
        self.playerState = playerState
        self.playerService = playerService
        self.artworkCache = artworkCache
        self.downloadService = downloadService
        self.modelContainer = modelContainer
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Number of tracks currently downloaded on this phone (candidates for watch sync).
    func downloadedTrackCount() -> Int {
        guard let modelContainer else { return 0 }
        let ctx = modelContainer.mainContext
        return (try? ctx.fetchCount(FetchDescriptor<DownloadedTrack>())) ?? 0
    }

    /// One-line description of the current watch link, for the picker header.
    func sessionSummary() -> String {
        guard WCSession.isSupported() else { return "Apple Watch not supported on this device" }
        let s = WCSession.default
        if s.activationState != .activated { return "Connecting to Apple Watch…" }
        if !s.isPaired { return "No Apple Watch paired" }
        if !s.isWatchAppInstalled { return "Diapason not installed on your watch" }
        return s.isReachable ? "Apple Watch connected" : "Apple Watch paired"
    }

    /// Downloaded playlists available to pick from for a scoped watch sync.
    func downloadedPlaylists() -> [WatchSyncablePlaylist] {
        guard let modelContainer else { return [] }
        let ctx = modelContainer.mainContext
        let playlists = (try? ctx.fetch(FetchDescriptor<DownloadedPlaylist>())) ?? []
        return playlists
            .map { WatchSyncablePlaylist(id: $0.playlistId, name: $0.name,
                                         coverArtId: $0.coverArtId, trackCount: $0.songIds.count) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Transfers only the downloaded tracks belonging to the chosen playlists.
    func syncPlaylists(_ playlistIds: [String]) async {
        guard let modelContainer else { return }
        let ctx = modelContainer.mainContext
        let selected = Set(playlistIds)
        let playlists = ((try? ctx.fetch(FetchDescriptor<DownloadedPlaylist>())) ?? [])
            .filter { selected.contains($0.playlistId) }
        let wantedSongIds = Set(playlists.flatMap(\.songIds))
        guard !wantedSongIds.isEmpty else { return }
        await transferTracks { wantedSongIds.contains($0.songId) }
    }

    /// Transfers every downloaded track (and its cover art) to the paired watch so
    /// it can be played on-device offline. Files queue in WCSession and deliver
    /// when the watch is reachable.
    func syncDownloadsToWatch() async {
        await transferTracks { _ in true }
    }

    /// Shared transfer loop: sends every downloaded track matching `include`
    /// (plus its cover art) to the watch, updating progress.
    private func transferTracks(where include: (DownloadedTrack) -> Bool) async {
        guard let modelContainer, let downloadService else {
            status = "Not ready. Try again in a moment."
            return
        }
        if let reason = blockingReason() {
            watchLog.error("Watch sync blocked: \(reason, privacy: .public)")
            status = reason
            return
        }
        let session = WCSession.default

        isSyncing = true
        status = ""
        defer { isSyncing = false }

        let ctx = modelContainer.mainContext
        let tracks = ((try? ctx.fetch(FetchDescriptor<DownloadedTrack>())) ?? []).filter(include)
        totalToSync = tracks.count
        syncedCount = 0
        watchLog.notice("Watch sync starting: \(tracks.count) track(s)")

        var sent = 0
        var missing = 0
        var sentCovers = Set<String>()
        for track in tracks {
            if let url = await downloadService.downloadedURL(forSongId: track.songId, serverId: track.serverId),
               FileManager.default.fileExists(atPath: url.path) {
                let meta: [String: Any] = [
                    "kind": "track",
                    "songId": track.songId,
                    "title": track.title,
                    "artist": track.artist ?? "",
                    "album": track.album ?? "",
                    "coverArtId": track.coverArtId ?? "",
                    "duration": track.durationSeconds ?? 0,
                    "suffix": track.suffix ?? url.pathExtension
                ]
                session.transferFile(url, metadata: meta)
                sent += 1
            } else {
                missing += 1
                watchLog.error("No local file for songId \(track.songId, privacy: .public)")
            }
            if let cover = track.coverArtId, !cover.isEmpty, !sentCovers.contains(cover),
               let coverURL = await downloadService.localCoverArtURL(forId: cover) {
                sentCovers.insert(cover)
                session.transferFile(coverURL, metadata: ["kind": "cover", "coverArtId": cover])
            }
            syncedCount += 1
        }

        let pending = session.outstandingFileTransfers.count
        watchLog.notice("Watch sync queued \(sent) file(s); \(missing) missing; \(pending) outstanding")
        status = sent == 0
            ? (missing > 0 ? "No playable files found for the selected items." : "Nothing to sync.")
            : "Queued \(sent) track\(sent == 1 ? "" : "s") to your watch. Keep both nearby until transfer completes."
    }

    /// Sends the current track + playback state to the watch. Cheap fields go every
    /// call; the artwork thumbnail is only re-encoded when the cover changes.
    func pushState() {
        guard WCSession.isSupported(), let playerState else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        var context: [String: Any] = [
            "title": playerState.currentTrack?.title ?? "",
            "artist": playerState.currentTrack?.artist ?? "",
            "isPlaying": playerState.playbackState == .playing,
            "hasTrack": playerState.currentTrack != nil,
            "duration": playerState.duration,
            "stamp": Date().timeIntervalSince1970
        ]

        if let coverId = playerState.currentTrack?.coverArtId {
            if coverId != lastArtworkId {
                lastArtworkId = coverId
                lastArtworkData = Self.thumbnailData(artworkCache?.cachedImage(for: coverId))
            }
            if let data = lastArtworkData { context["artwork"] = data }
        } else {
            lastArtworkId = nil
            lastArtworkData = nil
        }

        try? session.updateApplicationContext(context)
    }

    private static func thumbnailData(_ image: UIImage?) -> Data? {
        guard let image else { return nil }
        let side: CGFloat = 120
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return resized.jpegData(compressionQuality: 0.6)
    }

    private func handle(command: String) {
        guard let playerService else { return }
        Task { @MainActor in
            switch command {
            case "playPause": await playerService.togglePlayPause()
            case "next":      try? await playerService.skipToNext()
            case "previous":  try? await playerService.skipToPrevious()
            default: break
            }
        }
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.pushState() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = message["command"] as? String else { return }
        Task { @MainActor in
            self.handle(command: command)
            // Reflect the new state back promptly.
            try? await Task.sleep(for: .milliseconds(150))
            self.pushState()
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        let song = (fileTransfer.file.metadata?["songId"] as? String) ?? (fileTransfer.file.metadata?["coverArtId"] as? String) ?? "?"
        if let error {
            watchLog.error("File transfer FAILED (\(song, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        } else {
            watchLog.notice("File transfer finished OK (\(song, privacy: .public)); \(session.outstandingFileTransfers.count) remaining")
        }
    }
}
#endif
