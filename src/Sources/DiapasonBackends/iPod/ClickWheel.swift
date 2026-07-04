// Diapason — iPod click wheel control.
// Copyright (C) 2026 Arnaud BEUX
// Licensed under the GNU General Public License v3.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

struct ClickWheel: View {
    @ObservedObject var controller: iPodController
    var diameter: CGFloat = 260

    private var centerRadius: CGFloat { diameter * 0.19 }
    @State private var lastAngle: Double?
    @State private var accumulated: Double = 0
    private let stepDegrees: Double = 24

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.97), Color(white: 0.86)],
                                     center: .center, startRadius: centerRadius, endRadius: diameter / 2))
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

            VStack {
                Text("MENU").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(Color(white: 0.28)).padding(.top, diameter * 0.06)
                Spacer()
                Image(systemName: "playpause.fill").font(.system(size: 16, weight: .bold)).foregroundColor(Color(white: 0.32)).padding(.bottom, diameter * 0.07)
            }
            HStack {
                Image(systemName: "backward.end.fill").font(.system(size: 16, weight: .bold)).foregroundColor(Color(white: 0.32)).padding(.leading, diameter * 0.07)
                Spacer()
                Image(systemName: "forward.end.fill").font(.system(size: 16, weight: .bold)).foregroundColor(Color(white: 0.32)).padding(.trailing, diameter * 0.07)
            }
            .frame(width: diameter, height: diameter)

            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.99), Color(white: 0.88)], center: .center, startRadius: 0, endRadius: centerRadius))
                .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 1))
                .frame(width: centerRadius * 2, height: centerRadius * 2)
                .shadow(color: .black.opacity(0.08), radius: 2)
                .contentShape(Circle())
                .onTapGesture { controller.select() }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(rotationDrag)
        .simultaneousGesture(cardinalTap)
    }

    private var rotationDrag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let r = radius(value.location)
                guard r > centerRadius else { return }
                let a = angle(value.location)
                if let last = lastAngle {
                    var delta = a - last
                    if delta > 180 { delta -= 360 }
                    if delta < -180 { delta += 360 }
                    accumulated += delta
                    while accumulated >= stepDegrees { controller.scroll(by: 1); accumulated -= stepDegrees }
                    while accumulated <= -stepDegrees { controller.scroll(by: -1); accumulated += stepDegrees }
                }
                lastAngle = a
            }
            .onEnded { _ in lastAngle = nil; accumulated = 0 }
    }

    private var cardinalTap: some Gesture {
        SpatialTapGesture().onEnded { value in
            guard radius(value.location) > centerRadius else { return }
            switch cardinal(value.location) {
            case .top: controller.menuBack()
            case .bottom: controller.playPause()
            case .left: controller.previous()
            case .right: controller.next()
            }
        }
    }

    private enum Cardinal { case top, bottom, left, right }
    private func vec(_ p: CGPoint) -> CGVector { CGVector(dx: p.x - diameter / 2, dy: p.y - diameter / 2) }
    private func radius(_ p: CGPoint) -> CGFloat { let v = vec(p); return hypot(v.dx, v.dy) }
    private func angle(_ p: CGPoint) -> Double { let v = vec(p); return atan2(v.dy, v.dx) * 180 / .pi }
    private func cardinal(_ p: CGPoint) -> Cardinal {
        switch angle(p) {
        case -45..<45: return .right
        case 45..<135: return .bottom
        case -135 ..< -45: return .top
        default: return .left
        }
    }
}
