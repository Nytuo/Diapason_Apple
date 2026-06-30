import Foundation

/// Submits "now playing" + completed listens to Last.fm and ListenBrainz.
/// Reads account credentials from `UserDefaults` (same keys as DiscoveryFeedManager).
/// All calls are best-effort and no-op when the account isn't connected.
final class Scrobbler {
    static let shared = Scrobbler()
    private let defaults = UserDefaults.standard

    private var lbToken: String? {
        let t = defaults.string(forKey: "lb_token") ?? ""
        return t.isEmpty ? nil : t
    }
    private var lastFm: (key: String, secret: String, session: String)? {
        let k = defaults.string(forKey: "lfm_key") ?? ""
        let s = defaults.string(forKey: "lfm_secret") ?? ""
        let sk = defaults.string(forKey: "lfm_session") ?? ""
        return (k.isEmpty || sk.isEmpty) ? nil : (k, s, sk)
    }

    func nowPlaying(_ song: Song) {
        Task {
            if let token = lbToken {
                await ListenBrainzClient.shared.submitListen(
                    token: token, listenType: "playing_now",
                    artist: song.artist, track: song.title, album: song.album, listenedAt: nil)
            }
            if let lfm = lastFm {
                await LastFmClient.shared.updateNowPlaying(
                    apiKey: lfm.key, apiSecret: lfm.secret, sessionKey: lfm.session,
                    artist: song.artist, track: song.title, album: song.album, durationSec: song.duration)
            }
        }
    }

    func scrobble(_ song: Song, startedAt: TimeInterval) {
        let ts = Int(startedAt)
        Task {
            if let token = lbToken {
                await ListenBrainzClient.shared.submitListen(
                    token: token, listenType: "single",
                    artist: song.artist, track: song.title, album: song.album, listenedAt: ts)
            }
            if let lfm = lastFm {
                await LastFmClient.shared.scrobble(
                    apiKey: lfm.key, apiSecret: lfm.secret, sessionKey: lfm.session,
                    artist: song.artist, track: song.title, album: song.album, timestamp: ts)
            }
        }
    }
}
