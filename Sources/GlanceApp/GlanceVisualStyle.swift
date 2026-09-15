import AppKit
import SwiftUI

enum GlanceVisualStyle {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let groupedBackground = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let contentInset: CGFloat = 16
    static let cornerRadius: CGFloat = 10
}

/// The system material follows appearance, contrast, and transparency preferences.
struct GlancePanelBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            GlanceVisualStyle.canvas
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }
}
