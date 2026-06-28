import SwiftUI

enum BackendType: String, CaseIterable, Identifiable {
    case subsonic = "Subsonic / Navidrome"
    case plex = "Plex"
    var id: String { self.rawValue }
}

class BackendManager: ObservableObject {
    static let shared = BackendManager()
    
    @Published var activeType: BackendType = BackendType(rawValue: UserDefaults.standard.string(forKey: "activeBackendType") ?? "") ?? .subsonic {
        didSet {
            UserDefaults.standard.set(activeType.rawValue, forKey: "activeBackendType")
        }
    }
    
    var client: any MusicBackend {
        return UnifiedMusicClient.shared
    }
    
    func autoConnect() async {
        // Try to ping the current client
        _ = try? await client.ping()
    }
}
