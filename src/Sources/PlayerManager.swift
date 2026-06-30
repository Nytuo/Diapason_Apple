import SwiftUI
import AVFoundation
import CoreMedia
import Combine
import MediaPlayer

// MARK: - Repeat & Shuffle Modes

enum RepeatMode: String, CaseIterable {
    case off, all, one
    var systemImage: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
    var isActive: Bool { self != .off }
}

enum ShuffleMode: String, CaseIterable {
    case off, on
    var systemImage: String { "shuffle" }
    var isActive: Bool { self == .on }
}

// MARK: - PlaybackTimeTracker

/// Dedicated object for time updates to prevent full-app re-renders
@MainActor
class PlaybackTimeTracker: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
}

// MARK: - PlayerManager

@MainActor
class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    private var player: AVPlayer?
    private let commandCenter = MPRemoteCommandCenter.shared()
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()

    @Published var queue: [Song] = []
    @Published var currentIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var currentSong: Song?
    @Published var repeatMode: RepeatMode = .off
    @Published var shuffleMode: ShuffleMode = .off

    /// Sleep timer: when set, playback pauses at this date.
    @Published var sleepTimerEnd: Date? = nil
    private var sleepWorkItem: DispatchWorkItem?

    /// Original unshuffled queue, kept so we can unshuffle
    private var originalQueue: [Song] = []

    let timeTracker = PlaybackTimeTracker()
    private var timeObserver: Any?
    private var endObserver: Any?
    private var statusSubscription: AnyCancellable?

    // Scrobbling state for the currently playing item.
    private var scrobbleSongId: String?
    private var scrobbleStartedAt: TimeInterval = 0
    private var scrobbled = false

    init() {
        setupAudioSession()
        setupRemoteCommands()
    }

    // MARK: - Public Controls

    func play(queue: [Song], startingAt index: Int = 0) {
        originalQueue = queue
        if shuffleMode == .on {
            var shuffled = queue
            let selected = shuffled.remove(at: index)
            shuffled.shuffle()
            shuffled.insert(selected, at: 0)
            self.queue = shuffled
            self.currentIndex = 0
        } else {
            self.queue = queue
            self.currentIndex = index
        }
        playCurrent()
    }

    func playCurrent() {
        guard queue.indices.contains(currentIndex) else { return }
        let song = queue[currentIndex]

        if self.currentSong?.id != song.id {
            self.currentSong = song
        }

        // URL resolution: local → offline download → playback cache → stream
        if song.id.hasPrefix("local_song_") {
            if let url = LocalMusicManager.shared.getStreamURL(id: song.id) {
                playWithURL(url, for: song)
            }
        } else if let url = OfflineDownloadManager.shared.getDownloadedURL(forSongId: song.id) {
            print("▶︎ Playing \(song.title) from offline downloads")
            playWithURL(url, for: song)
        } else if let url = PlaybackCacheManager.shared.getCachedURL(forSongId: song.id) {
            print("▶︎ Playing \(song.title) from playback cache")
            playWithURL(url, for: song)
        } else {
            if let url = BackendManager.shared.client.getStreamURL(id: song.id) {
                playWithURL(url, for: song)
                PlaybackCacheManager.shared.cacheSongAsync(id: song.id, remoteURL: url)
            }
        }
    }

    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        nowPlayingInfoCenter.playbackState = isPlaying ? .playing : .paused
        updateNowPlaying()
        syncPlaybackProgress(time: timeTracker.currentTime, duration: timeTracker.duration)
    }

    func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
        updateNowPlaying(playbackTime: time)
        syncPlaybackProgress(time: time, duration: timeTracker.duration)
    }

    func next() {
        switch repeatMode {
        case .one:
            seek(to: 0)
            player?.play()
            isPlaying = true
        case .all:
            currentIndex = (currentIndex + 1) % queue.count
            playCurrent()
        case .off:
            if currentIndex < queue.count - 1 {
                currentIndex += 1
                playCurrent()
            } else {
                // End of queue — stop
                player?.pause()
                isPlaying = false
                nowPlayingInfoCenter.playbackState = .stopped
            }
        }
    }

    func previous() {
        // If past 3 seconds, restart current track
        if timeTracker.currentTime > 3 {
            seek(to: 0)
            player?.play()
            isPlaying = true
            return
        }
        if currentIndex > 0 {
            currentIndex -= 1
            playCurrent()
        } else {
            seek(to: 0)
            player?.play()
            isPlaying = true
        }
    }

    func toggleShuffle() {
        if shuffleMode == .off {
            shuffleMode = .on
            // Reshuffle keeping current song first
            if let current = currentSong {
                var rest = queue.filter { $0.id != current.id }
                rest.shuffle()
                queue = [current] + rest
                currentIndex = 0
            }
        } else {
            shuffleMode = .off
            // Restore original order, seek to current song position
            if let current = currentSong,
               let idx = originalQueue.firstIndex(where: { $0.id == current.id }) {
                queue = originalQueue
                currentIndex = idx
            }
        }
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        // Update remote control
        commandCenter.nextTrackCommand.isEnabled = repeatMode != .one || queue.count > 1
    }

    // MARK: - Sleep Timer

    func setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        guard minutes > 0 else { return }
        let end = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTimerEnd = end
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isPlaying { self.togglePlayPause() }
            self.sleepTimerEnd = nil
        }
        sleepWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(minutes) * 60, execute: work)
    }

    func cancelSleepTimer() {
        sleepWorkItem?.cancel()
        sleepWorkItem = nil
        sleepTimerEnd = nil
    }

    // MARK: - Playlist management (server-side, Subsonic)

    func addCurrentSongToPlaylist(playlistId: String) async {
        guard let song = currentSong else { return }
        await addSongToPlaylist(song: song, playlistId: playlistId)
    }

    func addSongToPlaylist(song: Song, playlistId: String) async {
        guard !song.id.hasPrefix("local_song_") else { return }
        try? await BackendManager.shared.client.addSongToPlaylist(songId: song.id, playlistId: playlistId)
    }

    // MARK: - Progress Sync

    func syncPlaybackProgress(time: Double, duration: Double) {
        guard let song = currentSong else { return }
        let state = isPlaying ? "playing" : "paused"
        Task {
            await BackendManager.shared.client.updateProgress(
                id: song.id,
                ratingKey: song.ratingKey,
                state: state,
                time: time,
                duration: duration
            )
        }
    }

    // MARK: - Private Playback

    private func playWithURL(_ url: URL, for song: Song) {
        // Remove previous observers
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        statusSubscription?.cancel()
        statusSubscription = nil

        let playerItem = AVPlayerItem(url: url)

        // For local files, observe status — AVPlayer fails silently if file is
        // unreadable (wrong content, bad extension hint, corrupted).
        // On failure: purge the bad record and fall back to streaming.
        if url.isFileURL {
            statusSubscription = playerItem.publisher(for: \.status)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    guard status == .failed else { return }
                    Task { @MainActor [weak self] in
                        self?.recoverFromLocalFailure(song: song, failedURL: url)
                    }
                }
        }

        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }

        player?.play()
        isPlaying = true

        // Announce "now playing" and reset scrobble tracking for the new track.
        if scrobbleSongId != song.id {
            scrobbleSongId = song.id
            scrobbleStartedAt = Date().timeIntervalSince1970
            scrobbled = false
            Scrobbler.shared.nowPlaying(song)
        }

        // Periodic time observer (register once)
        if timeObserver == nil {
            timeObserver = player?.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
                queue: .main
            ) { [weak self] time in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let secs = time.seconds.isNaN ? 0 : time.seconds
                    self.timeTracker.currentTime = secs
                    if let d = self.player?.currentItem?.duration.seconds, !d.isNaN, d > 0 {
                        self.timeTracker.duration = d
                        let currentInt = Int(secs)
                        if currentInt > 0 && currentInt % 5 == 0 {
                            self.syncPlaybackProgress(time: secs, duration: d)
                        }
                        // Scrobble once past the halfway point (capped at 4 min).
                        if !self.scrobbled, let cur = self.currentSong,
                           self.scrobbleSongId == cur.id, d > 30 {
                            if secs >= min(d / 2, 240) {
                                self.scrobbled = true
                                Scrobbler.shared.scrobble(cur, startedAt: self.scrobbleStartedAt)
                            }
                        }
                    }
                }
            }
        }

        updateNowPlaying()
        nowPlayingInfoCenter.playbackState = .playing
        syncPlaybackProgress(time: 0, duration: song.duration.map { Double($0) } ?? 0)

        // End-of-track: hop to MainActor then call next()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.next() }
        }
    }

    private func recoverFromLocalFailure(song: Song, failedURL: URL) {
        guard currentSong?.id == song.id else { return }
        print("⚠️ Local playback failed (\(failedURL.lastPathComponent)), purging record")
        statusSubscription?.cancel()
        statusSubscription = nil

        let songId = song.id

        if songId.hasPrefix("local_song_") {
            // Transferred file with no streaming fallback — skip
            next()
            return
        }

        // Purge bad offline and cache records so they won't be hit again
        OfflineDownloadManager.shared.deleteDownload(songId: songId)
        PlaybackCacheManager.shared.removeFromCache(songId: songId)

        // Fall back to streaming
        if let streamURL = BackendManager.shared.client.getStreamURL(id: songId) {
            playWithURL(streamURL, for: song)
        } else {
            next()
        }
    }

    // MARK: - Remote Commands

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session: \(error)")
        }
    }

    private func setupRemoteCommands() {
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                Task { @MainActor in self?.seek(to: event.positionTime) }
                return .success
            }
            return .commandFailed
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlaying(playbackTime: Double? = nil) {
        guard let song = currentSong else { return }
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = song.title
        info[MPMediaItemPropertyArtist] = song.artist
        info[MPMediaItemPropertyAlbumTitle] = song.album
        if let dur = song.duration { info[MPMediaItemPropertyPlaybackDuration] = dur }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackTime ?? timeTracker.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        nowPlayingInfoCenter.nowPlayingInfo = info

        if let artURL = BackendManager.shared.client.getCoverArtURL(id: song.albumId) {
            updateArtwork(url: artURL)
        }
    }

    private func updateArtwork(url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            DispatchQueue.main.async {
                var info = self.nowPlayingInfoCenter.nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = artwork
                self.nowPlayingInfoCenter.nowPlayingInfo = info
            }
        }.resume()
    }
}
