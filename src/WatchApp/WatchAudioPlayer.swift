// Diapason Watch — on-device audio playback of the offline library.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import Foundation
import AVFoundation
import Combine

@MainActor
final class WatchAudioPlayer: NSObject, ObservableObject {
    @Published private(set) var currentTrack: WatchTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var queue: [WatchTrack] = []
    private var index = 0
    private weak var store: WatchLibraryStore?
    private var ticker: AnyCancellable?

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
        if player.isPlaying { player.pause(); isPlaying = false }
        else { activateSession(); player.play(); isPlaying = true }
    }

    func next() {
        guard !queue.isEmpty else { return }
        index = (index + 1) % queue.count
        load(at: index, autoplay: true)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if position > 3, let player { player.currentTime = 0; position = 0; return }
        index = (index - 1 + queue.count) % queue.count
        load(at: index, autoplay: true)
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        position = time
    }

    // MARK: - Internals

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try? session.setActive(true)
    }

    private func load(at index: Int, autoplay: Bool) {
        guard let store, queue.indices.contains(index) else { return }
        let track = queue[index]
        let url = store.fileURL(for: track)
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            player = newPlayer
            currentTrack = track
            duration = newPlayer.duration
            position = 0
            if autoplay { newPlayer.play(); isPlaying = true }
            startTicker()
        } catch {
            // Skip unreadable file.
            isPlaying = false
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let player = self.player else { return }
                self.position = player.currentTime
                self.isPlaying = player.isPlaying
            }
    }
}

extension WatchAudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.next() }
    }
}
