// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

/// Tuning-fork (diapason) silhouette shape. Fill with `FillStyle(eoFill: true)` to punch through the gap between the tines.
struct DiapasonIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = w / 2

        let tineW   = w * 0.13          // thickness of each tine
        let halfGap = w * 0.105         // half the inner gap between tines
        let stemW   = w * 0.16          // stem width
        let stemR   = stemW * 0.3       // stem bottom-corner radius

        // Horizontal positions
        let lo = cx - halfGap - tineW   // left tine outer edge
        let li = cx - halfGap           // left tine inner edge
        let ri = cx + halfGap           // right tine inner edge
        let ro = cx + halfGap + tineW   // right tine outer edge
        let sl = cx - stemW / 2
        let sr = cx + stemW / 2

        // Top arc geometry
        let arcR   = (ro - lo) / 2      // outer arc radius — top of arc sits at rect top edge
        let arcInR = halfGap            // inner arc radius
        let arcCY  = arcR               // arc centre Y

        // Shoulder: where the stem fans out into the tines
        let splitY = h * 0.65
        let sY1    = splitY + h * 0.07  // shoulder bottom (stem side)
        let sY2    = splitY - h * 0.07  // shoulder top   (tine side)

        // ── Outer silhouette ──────────────────────────────────────────────
        path.move(to: CGPoint(x: sl + stemR, y: h))
        path.addLine(to: CGPoint(x: sr - stemR, y: h))
        path.addQuadCurve(to: CGPoint(x: sr, y: h - stemR),
                          control: CGPoint(x: sr, y: h))
        path.addLine(to: CGPoint(x: sr, y: sY1))
        // Right shoulder: stem right → right tine outer
        path.addCurve(to: CGPoint(x: ro, y: sY2),
                      control1: CGPoint(x: sr, y: splitY),
                      control2: CGPoint(x: ro, y: splitY))
        path.addLine(to: CGPoint(x: ro, y: arcCY))
        // Top outer arc — counter-clockwise on screen (Y-down) = goes over the top
        path.addArc(center: CGPoint(x: cx, y: arcCY), radius: arcR,
                    startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: lo, y: sY2))
        // Left shoulder: left tine outer → stem left
        path.addCurve(to: CGPoint(x: sl, y: sY1),
                      control1: CGPoint(x: lo, y: splitY),
                      control2: CGPoint(x: sl, y: splitY))
        path.addLine(to: CGPoint(x: sl, y: h - stemR))
        path.addQuadCurve(to: CGPoint(x: sl + stemR, y: h),
                          control: CGPoint(x: sl, y: h))
        path.closeSubpath()

        // ── Inner gap cutout (punch through with eoFill) ──────────────────
        let gapBotY = sY2 + h * 0.02
        path.move(to: CGPoint(x: li, y: gapBotY))
        path.addLine(to: CGPoint(x: li, y: arcCY))
        // Inner arc — clockwise in SwiftUI's Y-down coords = goes over the top
        path.addArc(center: CGPoint(x: cx, y: arcCY), radius: arcInR,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        path.addLine(to: CGPoint(x: ri, y: gapBotY))
        path.addLine(to: CGPoint(x: li, y: gapBotY))
        path.closeSubpath()

        return path
    }
}

#Preview {
    HStack(spacing: 24) {
        DiapasonIcon()
            .fill(DiapasonColors.accent, style: FillStyle(eoFill: true))
            .frame(width: 48, height: 72)

        DiapasonIcon()
            .fill(.white, style: FillStyle(eoFill: true))
            .frame(width: 36, height: 54)
            .padding(8)
            .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8))
    }
    .padding()
}
