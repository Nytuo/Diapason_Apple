// Diapason — extract a colourful palette from cover art for the tvOS backdrop.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

#if os(tvOS)
import SwiftUI
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

enum TVArtworkPalette {
    /// Downsamples the artwork to a small grid, reads the region colours, and
    /// returns up to `count` vibrant, hue-distinct colours actually present in the
    /// cover — so the Now Playing backdrop reflects the album, not a hue rotation.
    static func palette(from image: PlatformImage, count: Int = 4) -> [Color] {
        #if canImport(UIKit)
        guard let cg = image.cgImage else { return [] }
        let regions = regionColors(from: cg, grid: 5)
        return distinctVibrant(regions, count: count)
        #else
        return []
        #endif
    }

    #if canImport(UIKit)
    private struct Sample { let color: Color; let h: CGFloat; let s: CGFloat; let b: CGFloat }

    private static func regionColors(from cg: CGImage, grid: Int) -> [Sample] {
        let w = grid, h = grid
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var samples: [Sample] = []
        for i in stride(from: 0, to: data.count, by: 4) {
            let r = CGFloat(data[i]) / 255, g = CGFloat(data[i + 1]) / 255, b = CGFloat(data[i + 2]) / 255
            let ui = UIColor(red: r, green: g, blue: b, alpha: 1)
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
            ui.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
            samples.append(Sample(color: Color(red: r, green: g, blue: b), h: hue, s: sat, b: bri))
        }
        return samples
    }

    /// Greedily picks the most vibrant colours whose hues are spread apart, then
    /// pads (with the whole sorted list) if the art is near-monochrome.
    private static func distinctVibrant(_ samples: [Sample], count: Int) -> [Color] {
        let sorted = samples
            .filter { $0.b > 0.12 }                       // drop near-black
            .sorted { ($0.s * $0.b) > ($1.s * $1.b) }     // vibrancy = saturation × brightness
        guard !sorted.isEmpty else { return [] }

        var picked: [Sample] = []
        for s in sorted {
            if picked.count >= count { break }
            if picked.allSatisfy({ hueDistance($0.h, s.h) > 0.05 }) { picked.append(s) }
        }
        // Near-monochrome cover: pad from the sorted list so the mesh still has 4 stops.
        var i = 0
        while picked.count < count, i < sorted.count { picked.append(sorted[i]); i += 1 }
        return picked.map(\.color)
    }

    private static func hueDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let d = abs(a - b)
        return min(d, 1 - d)
    }
    #endif
}
#endif
