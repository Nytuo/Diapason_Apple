// Diapason Watch — playback, from a download or straight from the server.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import AVFoundation
import Combine
import Foundation

/// Plays on the watch itself.
///
/// Built on `AVPlayer` rather than `AVAudioPlayer` — the latter can only play a
/// local file, and half the point here is streaming from the music server with
/// the phone left at home. A downloaded track plays from disk; anything else
/// plays from its server URL. The rest of the app does not care which.
@MainActor
final class WatchAudioPlayer: NSObject, ObservableObject {
    @Published private(set) var currentTrack: WatchTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    /// Whether the current track is coming off the watch rather than the network.
    @Published private(set) var isOffline = false

    private var player: AVPlayer?
    private var queue: [WatchTrack] = []
    private var index = 0
    private weak var store: WatchLibraryStore?

    private var ticker: AnyCancellable?
    private var endObserver: NSObjectProtocol?

    func configure(store: WatchLibraryStore) {
        self.store = store
    }

    func play(_ tracks: [WatchTrack], startAt startIndex: Int) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        index = min(max(startIndex, 0), tracks.count - 1)
        activateSession()
        load(at: index, autoplay: true)
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            activateSession()
            player.play()
            isPlaying = true
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        index = (index + 1) % queue.count
        load(at: index, autoplay: true)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        // Match every music player ever: "previous" restarts the track first.
        if position > 3 {
            seek(to: 0)
            return
        }
        index = (index - 1 + queue.count) % queue.count
        load(at: index, autoplay: true)
    }

    func seek(to time: TimeInterval) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        position = time
    }

    // MARK: - Internals

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        // longFormAudio is what lets a watch play with the screen off, and over
        // Bluetooth headphones without the phone.
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try? session.setActive(true)
    }

    private func load(at index: Int, autoplay: Bool) {
        guard queue.indices.contains(index) else { return }
        let track = queue[index]

        // A downloaded file always wins: it needs no network and no server.
        let localURL = store?.fileURL(for: track)
        let url: URL?
        if let localURL, FileManager.default.fileExists(atPath: localURL.path) {
            url = localURL
            isOffline = true
        } else {
            url = URL(string: track.streamUrl)
            isOffline = false
        }
        guard let url else { return }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        currentTrack = track
        position = 0
        duration = TimeInterval(track.duration)
        isBuffering = !isOffline

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.next() }
        }

        if autoplay {
            newPlayer.play()
            isPlaying = true
        }
        startTicker()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let player = self.player else { return }

                self.position = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
                self.isPlaying = player.timeControlStatus == .playing
                self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate

                // The catalogue's duration is metadata; once the item loads, the
                // real one is better.
                if let itemDuration = player.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
            }
    }

    // No deinit: `endObserver` is MainActor-isolated and deinit is not, so
    // touching it there is a concurrency error. The observer is replaced on every
    // load and dies with the player, so there is nothing to clean up.
}
