import AppKit
import SwiftUI

enum GlanceVisualStyle {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let primarySurface = Color(nsColor: .controlBackgroundColor).opacity(0.78)
    static let insetSurface = Color(nsColor: .underPageBackgroundColor).opacity(0.58)
    static let subtleSurface = Color(nsColor: .controlBackgroundColor).opacity(0.52)
    static let accentTint = Color(nsColor: .controlAccentColor).opacity(0.09)
    static let accentStrongTint = Color(nsColor: .controlAccentColor).opacity(0.13)
    static let accentForeground = Color(nsColor: .controlAccentColor).opacity(0.88)
    static let activeControlSurface = Color(nsColor: .controlBackgroundColor).opacity(0.9)
    static let activeControlBorder = Color(nsColor: .controlAccentColor).opacity(0.18)
    static let controlShadow = Color.black.opacity(0.08)
    static let warningTint = Color.orange.opacity(0.08)
    static let warningBorder = Color.orange.opacity(0.14)
    static let border = Color(nsColor: .separatorColor).opacity(0.08)
    static let quietBorder = Color(nsColor: .separatorColor).opacity(0.05)
    static let divider = Color(nsColor: .separatorColor).opacity(0.09)
}

enum GlanceSurfaceTone {
    case primary
    case inset
    case subtle
    case accent
}

struct GlanceCardBackground: View {
    var tone: GlanceSurfaceTone = .primary
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }

    private var fillColor: Color {
        switch tone {
        case .primary:
            return GlanceVisualStyle.primarySurface
        case .inset:
            return GlanceVisualStyle.insetSurface
        case .subtle:
            return GlanceVisualStyle.subtleSurface
        case .accent:
            return GlanceVisualStyle.accentTint
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary, .inset:
            return GlanceVisualStyle.border
        case .subtle, .accent:
            return GlanceVisualStyle.quietBorder
        }
    }
}

struct GlanceDivider: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(GlanceVisualStyle.divider)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}
