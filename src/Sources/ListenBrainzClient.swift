import Foundation

// MARK: - Models

struct LBFreshRelease: Identifiable {
    let id: String          // release_mbid
    let releaseName: String
    let artistName: String
    let releaseDate: String?
    let coverArtURL: URL?
}

// MARK: - Decodable helpers (internal)

private struct LBFreshReleasesResponse: Decodable {
    struct Payload: Decodable {
        let releases: [LBReleaseRaw]
    }
    let payload: Payload
}

private struct LBReleaseRaw: Decodable {
    let release_mbid: String
    let release_name: String
    let artist_credit_name: String
    let release_date: String?
    let caa_id: Int64?
    let caa_release_mbid: String?
}

// MARK: - Client

class ListenBrainzClient {
    static let shared = ListenBrainzClient()
    private let session = URLSession.shared
    private let userAgent = "Diapason iOS/1.0 (music player)"

    func getFreshReleases(days: Int = 7, limit: Int = 30) async -> [LBFreshRelease] {
        var components = URLComponents(string: "https://api.listenbrainz.org/1/explore/fresh-releases")!
        components.queryItems = [
            URLQueryItem(name: "days",    value: "\(days)"),
            URLQueryItem(name: "sort",    value: "release_date"),
            URLQueryItem(name: "past",    value: "true"),
            URLQueryItem(name: "future",  value: "false")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(LBFreshReleasesResponse.self, from: data)
            return decoded.payload.releases
                .prefix(limit)
                .map { raw in
                    let coverURL = coverArtURL(mbid: raw.caa_release_mbid ?? raw.release_mbid)
                    return LBFreshRelease(
                        id: raw.release_mbid,
                        releaseName: raw.release_name,
                        artistName: raw.artist_credit_name,
                        releaseDate: raw.release_date,
                        coverArtURL: coverURL
                    )
                }
        } catch {
            print("ListenBrainz fresh-releases error: \(error)")
            return []
        }
    }

    private func coverArtURL(mbid: String) -> URL? {
        URL(string: "https://coverartarchive.org/release/\(mbid)/front-250")
    }
}
