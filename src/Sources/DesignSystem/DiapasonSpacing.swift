// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

// MARK: - Spacing scale (4pt grid)

enum DiapasonSpacing {
    static let xs: CGFloat    = 4
    static let s: CGFloat     = 8
    static let m: CGFloat     = 12
    static let l: CGFloat     = 16   // default horizontal screen padding
    static let xl: CGFloat    = 20
    static let xxl: CGFloat   = 24   // between sections
    static let xxxl: CGFloat  = 32
    static let xxxxl: CGFloat = 48

    /// Bottom scroll margin reserved for the iOS tabViewBottomAccessory mini player,
    /// which floats over tab content without extending the safe area.
    static let miniPlayerBottomMargin: CGFloat = 80
}

// MARK: - Corner radius scale

enum DiapasonCornerRadius {
    static let xs: CGFloat       = 4
    static let s: CGFloat        = 6
    static let standard: CGFloat = 8    // all cover arts, most cards
    static let large: CGFloat     = 12   // full-player cover art, sheets
    static let hero: CGFloat      = 20   // Wrapped stat hero, year card
    static let pill: CGFloat      = 999  // capsule buttons
}

// MARK: - Shadow presets

/// Cassette shadow values. In dark mode, shadows are invisible against black backgrounds;
/// use `CassetteCoverModifier` (via `.cassetteCoverStyle()`) which switches to a thin
/// border in dark mode automatically.
enum DiapasonShadow {
    static let coverRadius: CGFloat  = 8
    static let coverY: CGFloat       = 4
    static let coverOpacity: Double  = 0.15
}


// MARK: - View modifier: content width

struct ContentWidthModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func diapasonContentWidth() -> some View {
        modifier(ContentWidthModifier())
    }
}

// MARK: - View modifier: cover art style

struct DiapasonCoverModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: colorScheme == .dark ? .clear : .black.opacity(0.1),
                radius: 2,
                y: 1
            )
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.diapasonCoverBorder, lineWidth: 1)
                }
            }
    }
}

extension View {
    /// Clips to a rounded rectangle, adds shadow in light mode and a thin border in dark mode.
    func diapasonCoverStyle(cornerRadius: CGFloat = DiapasonCornerRadius.standard) -> some View {
        modifier(DiapasonCoverModifier(cornerRadius: cornerRadius))
    }
}
