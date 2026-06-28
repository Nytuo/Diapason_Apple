import Foundation

struct CachedFileRecord: Codable {
    let id: String
    let fileName: String
    let cachedAt: Date
    let fileSize: Int64
}

class PlaybackCacheManager: ObservableObject {
    static let shared = PlaybackCacheManager()
    
    private let fileManager = FileManager.default
    
    var maxTracks: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: "cache_max_tracks")
            return val == 0 ? 50 : val // default to 50 tracks
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "cache_max_tracks")
            queue.async {
                self.evictToLimit()
                self.saveIndex()
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    func getCacheSizeInBytes() -> Int64 {
        return queue.sync {
            records.reduce(0) { $0 + $1.fileSize }
        }
    }
    
    func getCachedTracksCount() -> Int {
        return queue.sync {
            records.count
        }
    }
    
    func clearCache() {
        queue.sync {
            for record in records {
                let fileURL = cacheDir.appendingPathComponent(record.fileName)
                try? fileManager.removeItem(at: fileURL)
            }
            records.removeAll()
            saveIndex()
        }
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func removeFromCache(songId: String) {
        queue.sync {
            guard let record = records.first(where: { $0.id == songId }) else { return }
            let fileURL = cacheDir.appendingPathComponent(record.fileName)
            try? fileManager.removeItem(at: fileURL)
            records.removeAll(where: { $0.id == songId })
            saveIndex()
        }
        DispatchQueue.main.async { self.objectWillChange.send() }
    }
    
    private var cacheDir: URL {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("audio_cache", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var indexURL: URL {
        return cacheDir.appendingPathComponent("cache_index.json")
    }
    
    private var records: [CachedFileRecord] = []
    private let queue = DispatchQueue(label: "com.diapason.cache", qos: .background)
    
    private init() {
        loadIndex()
    }
    
    private func loadIndex() {
        guard fileManager.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL) else {
            return
        }
        records = (try? JSONDecoder().decode([CachedFileRecord].self, from: data)) ?? []
    }
    
    private func saveIndex() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: indexURL)
        }
    }
    
    func getCachedURL(forSongId songId: String) -> URL? {
        queue.sync {
            guard let record = records.first(where: { $0.id == songId }) else { return nil }
            let fileURL = cacheDir.appendingPathComponent(record.fileName)
            
            // Validate the file exists and has the expected size
            let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path)
            let actualSize = (attrs?[.size] as? Int64) ?? 0
            
            guard actualSize > 0, actualSize == record.fileSize else {
                // Self-heal: remove corrupted or missing file record
                records.removeAll(where: { $0.id == songId })
                try? fileManager.removeItem(at: fileURL)
                saveIndex()
                return nil
            }
            
            // Touch the entry to update timestamp (optional)
            if let index = records.firstIndex(where: { $0.id == songId }) {
                let current = records[index]
                records.remove(at: index)
                records.append(CachedFileRecord(id: current.id, fileName: current.fileName, cachedAt: Date(), fileSize: current.fileSize))
                saveIndex()
            }
            
            return fileURL
        }
    }
    
    func cacheSongAsync(id: String, remoteURL: URL) {
        // Avoid double caching (thread safe check)
        var alreadyCached = false
        queue.sync {
            alreadyCached = self.records.contains(where: { $0.id == id })
        }
        if alreadyCached { return }
        
        Task { [weak self] in
            guard let self = self else { return }

            do {
                // Download first to determine actual audio format from Content-Type
                let (tempLocalURL, response) = try await URLSession.shared.download(from: remoteURL)

                let mimeType = (response as? HTTPURLResponse)?.mimeType ?? ""
                let fileExtension = Self.audioExtension(forMimeType: mimeType)
                    ?? (remoteURL.pathExtension.lowercased().isEmpty ? "mp3" : remoteURL.pathExtension.lowercased())
                let fileName = "\(id).\(fileExtension)"
                let targetURL = self.cacheDir.appendingPathComponent(fileName)
                
                // Copy/Rename file
                if self.fileManager.fileExists(atPath: targetURL.path) {
                    try? self.fileManager.removeItem(at: targetURL)
                }
                try self.fileManager.moveItem(at: tempLocalURL, to: targetURL)
                
                let size = (try? self.fileManager.attributesOfItem(atPath: targetURL.path)[.size] as? Int64) ?? 0
                
                self.queue.async {
                    self.records.removeAll(where: { $0.id == id })
                    self.records.append(CachedFileRecord(id: id, fileName: fileName, cachedAt: Date(), fileSize: size))
                    self.evictToLimit()
                    self.saveIndex()
                    print("Successfully cached remote song \(id) (\(size) bytes)")
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                    }
                }
            } catch {
                print("Failed to cache remote song \(id): \(error)")
            }
        }
    }
    
    private func evictToLimit() {
        while records.count > maxTracks {
            let oldest = records.removeFirst()
            let fileURL = cacheDir.appendingPathComponent(oldest.fileName)
            try? fileManager.removeItem(at: fileURL)
            print("Evicted song \(oldest.id) from playback cache")
        }
    }

    private static func audioExtension(forMimeType mime: String) -> String? {
        switch mime.lowercased().components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) {
        case "audio/mpeg", "audio/mp3":              return "mp3"
        case "audio/flac", "audio/x-flac":           return "flac"
        case "audio/aac":                             return "aac"
        case "audio/mp4", "audio/x-m4a", "audio/m4a": return "m4a"
        case "audio/ogg":                             return "ogg"
        case "audio/opus":                            return "opus"
        case "audio/wav", "audio/x-wav":              return "wav"
        case "audio/aiff", "audio/x-aiff":           return "aiff"
        default:                                      return nil
        }
    }
}
