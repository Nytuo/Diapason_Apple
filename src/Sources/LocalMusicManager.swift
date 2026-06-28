import Foundation
import AVFoundation
import UIKit

class LocalMusicManager: ObservableObject {
    static let shared = LocalMusicManager()
    
    @Published var songs: [Song] = []
    @Published var albums: [Album] = []
    @Published var artists: [Artist] = []
    
    private let fileManager = FileManager.default
    
    private var baseDir: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("local_music", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var filesDir: URL {
        let dir = baseDir.appendingPathComponent("files", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    var coversDirURL: URL {
        let dir = baseDir.appendingPathComponent("covers", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var dbURL: URL {
        return baseDir.appendingPathComponent("db.json")
    }
    
    private init() {
        loadDatabase()
    }
    
    func loadDatabase() {
        guard fileManager.fileExists(atPath: dbURL.path),
              let data = try? Data(contentsOf: dbURL) else {
            return
        }
        
        struct LocalDB: Codable {
            let songs: [Song]
            let albums: [Album]
            let artists: [Artist]
        }
        
        if let db = try? JSONDecoder().decode(LocalDB.self, from: data) {
            self.songs = db.songs
            self.albums = db.albums
            self.artists = db.artists
        }
    }
    
    func saveDatabase() {
        struct LocalDB: Codable {
            let songs: [Song]
            let albums: [Album]
            let artists: [Artist]
        }
        
        let db = LocalDB(songs: songs, albums: albums, artists: artists)
        if let data = try? JSONEncoder().encode(db) {
            try? data.write(to: dbURL)
        }
    }
    
    func importFile(from url: URL, filename: String) async -> Song? {
        let songId = "local_song_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let extFromFilename = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let extFromURL = url.pathExtension.lowercased()
        let fileExtension = extFromFilename.isEmpty ? (extFromURL.isEmpty ? "mp3" : extFromURL) : extFromFilename
        let targetFilename = "\(songId).\(fileExtension)"
        let targetURL = filesDir.appendingPathComponent(targetFilename)
        
        // Remove existing file if any
        if fileManager.fileExists(atPath: targetURL.path) {
            try? fileManager.removeItem(at: targetURL)
        }
        
        do {
            try fileManager.copyItem(at: url, to: targetURL)
        } catch {
            print("Failed to copy local file: \(error)")
            return nil
        }
        
        return await parseAndIndexFile(at: targetURL, filename: filename, songId: songId)
    }
    
    private func parseAndIndexFile(at fileURL: URL, filename: String, songId: String) async -> Song? {
        let asset = AVAsset(url: fileURL)
        var title = filename
        var artistName = "Unknown Artist"
        var albumName = "Unknown Album"
        var trackNumber: Int? = nil
        var duration: Int = 0
        var artworkData: Data? = nil
        
        // Read duration
        if let durationSecs = try? await asset.load(.duration).seconds, !durationSecs.isNaN {
            duration = Int(durationSecs)
        }
        
        // Read common metadata
        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    title = (try? await item.load(.value) as? String) ?? title
                case .commonKeyArtist:
                    artistName = (try? await item.load(.value) as? String) ?? artistName
                case .commonKeyAlbumName:
                    albumName = (try? await item.load(.value) as? String) ?? albumName
                case .commonKeyArtwork:
                    if let val = try? await item.load(.value) {
                        if let data = val as? Data {
                            artworkData = data
                        } else if let dict = val as? [String: Any], let data = dict["data"] as? Data {
                            artworkData = data
                        }
                    }
                default:
                    break
                }
            }
        }
        
        // Read format metadata (APIC / covr and tracks)
        if let formatMetadata = try? await asset.load(.metadata) {
            for item in formatMetadata {
                if artworkData == nil {
                    if let key = item.commonKey, key == .commonKeyArtwork {
                        if let val = try? await item.load(.value) {
                            if let data = val as? Data {
                                artworkData = data
                            } else if let dict = val as? [String: Any], let data = dict["data"] as? Data {
                                artworkData = data
                            }
                        }
                    } else if let key = item.key as? String, key == "APIC" || key == "covr" {
                        if let val = try? await item.load(.value) {
                            if let data = val as? Data {
                                artworkData = data
                            } else if let dict = val as? [String: Any], let data = dict["data"] as? Data {
                                artworkData = data
                            }
                        }
                    }
                }
                
                if let key = item.key as? String, key.contains("TRCK") || key.contains("track") {
                    if let val = try? await item.load(.value) as? String, let num = Int(val.components(separatedBy: "/")[0]) {
                        trackNumber = num
                    } else if let val = try? await item.load(.value) as? Int {
                        trackNumber = val
                    }
                }
            }
        }
        
        let cleanArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        let artistId = "local_art_" + cleanArtist.components(separatedBy: CharacterSet.alphanumerics.inverted).joined().lowercased()
        let albumId = "local_alb_" + (cleanArtist + "_" + cleanAlbum).components(separatedBy: CharacterSet.alphanumerics.inverted).joined().lowercased()
        
        var coverArtPath: String? = nil
        if let artData = artworkData {
            let coverURL = coversDirURL.appendingPathComponent("\(albumId).jpg")
            try? artData.write(to: coverURL)
            coverArtPath = coverURL.path
        }
        
        let newSong = Song(
            id: songId,
            title: title,
            artist: artistName,
            artistId: artistId,
            album: albumName,
            albumId: albumId,
            duration: duration,
            track: trackNumber,
            coverArt: coverArtPath,
            ratingKey: nil,
            bitRate: nil
        )
        
        await MainActor.run {
            // Update songs
            if !self.songs.contains(where: { $0.title == newSong.title && $0.artist == newSong.artist && $0.album == newSong.album }) {
                self.songs.append(newSong)
            }
            
            // Update artists
            if !self.artists.contains(where: { $0.id == artistId }) {
                self.artists.append(Artist(id: artistId, name: artistName, albumCount: 1, coverArt: coverArtPath))
            }
            
            // Update albums
            if !self.albums.contains(where: { $0.id == albumId }) {
                self.albums.append(Album(id: albumId, name: albumName, title: albumName, artist: artistName, artistId: artistId, coverArt: coverArtPath, year: nil))
            }
            
            self.saveDatabase()
        }
        
        return newSong
    }
    
    func getStreamURL(id: String) -> URL? {
        // Let's find any file in filesDir that matches the songId exactly (irrespective of extension)
        let files = (try? fileManager.contentsOfDirectory(at: filesDir, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.deletingPathExtension().lastPathComponent == id }
    }
    
    func deleteLocalSong(id: String) {
        guard let song = songs.first(where: { $0.id == id }) else { return }
        
        // Remove file from disk
        if let fileURL = getStreamURL(id: id) {
            try? fileManager.removeItem(at: fileURL)
        }
        
        // Remove song from lists
        songs.removeAll(where: { $0.id == id })
        
        // Remove album if no songs remain
        let albumId = song.albumId
        if !songs.contains(where: { $0.albumId == albumId }) {
            albums.removeAll(where: { $0.id == albumId })
            let coverURL = coversDirURL.appendingPathComponent("\(albumId).jpg")
            try? fileManager.removeItem(at: coverURL)
        }
        
        // Remove artist if no songs remain
        let artistId = song.artistId
        if !songs.contains(where: { $0.artistId == artistId }) {
            artists.removeAll(where: { $0.id == artistId })
        }
        
        saveDatabase()
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}
