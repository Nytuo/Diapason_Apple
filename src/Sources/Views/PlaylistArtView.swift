import SwiftUI

struct PlaylistArtView: View {
    let playlist: Playlist
    @EnvironmentObject var backend: BackendManager

    var body: some View {
        if let artId = playlist.coverArt, let url = backend.client.getCoverArtURL(id: artId) {
            DiapasonArtworkView(url: url)
                .scaledToFill()
        } else {
            placeholder
        }
    }

    var placeholder: some View {
        ZStack {
            Rectangle().fill(Color.customTertiarySystemGroupedBackground)
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }
}
