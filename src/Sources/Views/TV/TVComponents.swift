// Diapason — shared tvOS UI components (focus-first cards, rails, rows).
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

#if os(tvOS)
import SwiftUI

// MARK: - Metrics

enum TVMetrics {
    static let screenH: CGFloat = 80          // horizontal screen edge padding
    static let screenTop: CGFloat = 40
    static let railSpacing: CGFloat = 56       // vertical gap between rails
    static let cardSpacing: CGFloat = 40       // gap between cards in a rail
    static let posterSize: CGFloat = 240       // album/playlist poster edge
    static let artistSize: CGFloat = 220       // artist circle diameter
    static let cardCorner: CGFloat = 12
}

// MARK: - Poster link (album / playlist)

/// Focus-first poster: only the square artwork is the focusable `.card` button;
/// the title + subtitle live BELOW it, outside the button, so the tvOS focus lift
/// never scales over or clips the text. Navigates to `value` on select.
struct TVPosterLink<V: Hashable>: View {
    let value: V
    let coverArtId: String?
    let title: String
    var subtitle: String? = nil
    var size: CGFloat = TVMetrics.posterSize
    var placeholder: String = "music.note"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: value) {
                CoverArtView(id: coverArtId ?? "", size: Int(size * 2), cornerRadius: TVMetrics.cardCorner,
                             placeholderSystemImage: placeholder)
                    .frame(width: size, height: size)
            }
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle ?? " ")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: size, alignment: .leading)
        }
        .frame(width: size)
    }
}

/// Circular artist link. Artwork focusable; name centered below, outside the card.
struct TVArtistLink<V: Hashable>: View {
    let value: V
    let coverArtId: String?
    let name: String
    var size: CGFloat = TVMetrics.artistSize

    var body: some View {
        VStack(spacing: 16) {
            NavigationLink(value: value) {
                CoverArtView(id: coverArtId ?? "", size: Int(size * 2), cornerRadius: size / 2,
                             placeholderSystemImage: "person.fill")
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
            .buttonStyle(.card)

            Text(name)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: size + 40)
                .multilineTextAlignment(.center)
        }
        .frame(width: size + 40)
    }
}

// MARK: - Section header

struct TVSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            trailing()
        }
    }
}

extension TVSectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title, trailing: { EmptyView() })
    }
}

// MARK: - Horizontal rail

/// A titled one-line horizontal scroller with an optional "See All" link.
struct TVRail<Item: Identifiable, Card: View>: View {
    let title: String
    let items: [Item]
    var seeAll: TVLibrarySection? = nil
    @ViewBuilder var card: (Item) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            TVSectionHeader(title: title) {
                if let seeAll {
                    NavigationLink(value: seeAll) {
                        HStack(spacing: 6) {
                            Text("See All")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 24, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.cassetteAccent)
                }
            }
            .padding(.horizontal, TVMetrics.screenH)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: TVMetrics.cardSpacing) {
                    ForEach(items) { item in
                        card(item)
                    }
                }
                .padding(.horizontal, TVMetrics.screenH)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Song row

/// Focus-first track row: index / play affordance, title + artist, duration.
struct TVSongRow: View {
    let index: Int
    let song: DisplayableSong
    var isCurrent: Bool = false

    var body: some View {
        HStack(spacing: 28) {
            CoverArtView(id: song.coverArtId ?? "", size: 120, cornerRadius: 6)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.system(size: 26, weight: isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent ? Color.cassetteAccent : .primary)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 20)
            Text(Self.duration(song.duration))
                .font(.system(size: 22).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 28)
        .contentShape(Rectangle())
    }

    static func duration(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "--:--" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
#endif
