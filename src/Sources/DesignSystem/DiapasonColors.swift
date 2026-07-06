// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

// MARK: - Cassette Design Tokens v1.8.1
// Rebrand: Electric Violet (#6C47F5) — replaces orange (#FF7F3F)
// All colors are adaptive (light/dark) via Asset Catalog Color Sets.
// Asset Catalog entries must be created alongside this file (see spec below).

public enum DiapasonColors {
    
    // MARK: — Accent
    /// Primary brand color. CTA, active icons, progress bars, play button.
    /// Light: #6C47F5 — Dark: #8060F7 (slightly lighter for contrast on dark bg)
    public static let accent = Color("Accent")
    
    /// Tinted background for badges, pills, active states.
    /// Light: #EDE9FE — Dark: #221E38
    public static let accentBackground = Color("AccentBackground")
    
    /// Text/icon color on top of accentBackground.
    /// Light: #4C28D4 — Dark: #9F86FA
    public static let accentForeground = Color("AccentForeground")
    
    // MARK: — Backgrounds
    /// App-level background. Subtly violet-tinted near-white / deep violet-black.
    /// Light: #F6F4FF — Dark: #0F0D1A
    public static let backgroundPrimary = Color("BackgroundPrimary")
    
    /// Cards, list rows, bottom sheets, grouped table backgrounds.
    /// Light: #EDEAFF — Dark: #1A1728
    public static let backgroundSecondary = Color("BackgroundSecondary")
    
    /// Elevated content: modals, popovers, context menus.
    /// Light: #FFFFFF — Dark: #231F35
    public static let backgroundTertiary = Color("BackgroundTertiary")
    
    // MARK: — Text
    /// Primary content: titles, song names, main body text.
    /// Light: #1A1520 — Dark: #F0EEF8
    public static let textPrimary = Color("TextPrimary")
    
    /// Supporting content: artist names, subtitles, descriptions.
    /// Light: #6B5F8A — Dark: #8C7DB8
    public static let textSecondary = Color("TextSecondary")
    
    /// De-emphasized content: durations, placeholders, hints, timestamps.
    /// Light: #9B8EBF — Dark: #5E5080
    public static let textTertiary = Color("TextTertiary")
    
    // MARK: — Structure
    /// List separators, dividers.
    /// Light: violet @ 12% opacity — Dark: violet @ 15% opacity
    public static let separator = Color("Separator")
    
    /// Card borders, input outlines.
    /// Light: violet @ 18% opacity — Dark: violet @ 22% opacity
    public static let border = Color("Border")
    
    // MARK: — Violet Ramp (raw stops, light-mode only — use for gradients, artwork tints, etc.)
    public enum Violet {
        public static let v50  = Color(hex: "#F0ECFF")
        public static let v100 = Color(hex: "#DDD5FE")
        public static let v200 = Color(hex: "#C0B0FC")
        public static let v300 = Color(hex: "#9F86FA")
        public static let v400 = Color(hex: "#8060F7")
        public static let v500 = Color(hex: "#6C47F5") // base accent
        public static let v600 = Color(hex: "#5530D4")
        public static let v700 = Color(hex: "#3F1FAF")
        public static let v800 = Color(hex: "#2D1480")
        public static let v900 = Color(hex: "#1B0A52")
    }
}

// MARK: - Color(hex:) helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
