// Cassette — Music client for Subsonic/OpenSubsonic servers
// Copyright (C) 2026 Mathieu Dubart
// Licensed under the Mozilla Public License 2.0.
// See LICENSE file in the project root for full license information.

import SwiftUI

// MARK: - Toast view

struct ToastView: View {
    let toast: ToastService.Toast

    var body: some View {
        HStack(spacing: DiapasonSpacing.s) {
            Image(systemName: toast.style.systemImage)
                .foregroundStyle(toast.style.tint)
            Text(toast.message)
                .font(.CellTitle)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, DiapasonSpacing.l)
        .padding(.vertical, DiapasonSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: DiapasonCornerRadius.large)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DiapasonCornerRadius.large)
                .stroke(toast.style.tint.opacity(0.3), lineWidth: 1)
        )
        .shadow(radius: 8, y: 2)
        .padding(.horizontal, DiapasonSpacing.l)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Overlay modifier

struct ToastOverlay: ViewModifier {
    @Environment(ToastService.self) private var toastService

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toastService.current {
                    ToastView(toast: toast)
                        .padding(.top, DiapasonSpacing.s)
                        .id(toast.id)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastService.current)
    }
}

extension View {
    func toastOverlay() -> some View {
        modifier(ToastOverlay())
    }
}
