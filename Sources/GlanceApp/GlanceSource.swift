import Foundation

struct GlanceSource: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let detail: String

    var logoAssetName: String? {
        switch id {
        case "opencode-local":
            return "opencode"
        case "codex-local":
            return "codex"
        case "claude-local":
            return "claude-code"
        case "gemini-local":
            return "gemini-cli"
        default:
            return nil
        }
    }

    var systemImageName: String {
        switch id {
        case "opencode-local":
            return "apple.terminal"
        case "codex-local":
            return "circle.hexagongrid"
        case "claude-local":
            return "quote.bubble"
        case "gemini-local":
            return "diamond"
        default:
            return "square.stack.3d.up"
        }
    }
}

enum GlanceSources {
    static let openCodeLocal = GlanceSource(
        id: "opencode-local",
        displayName: "OpenCode",
        detail: "Current local source"
    )

    static let claudeCodeLocal = GlanceSource(
        id: "claude-local",
        displayName: "Claude Code",
        detail: "Current local source"
    )

    static let codexLocal = GlanceSource(
        id: "codex-local",
        displayName: "Codex",
        detail: "Current local source"
    )

    static let geminiCLILocal = GlanceSource(
        id: "gemini-local",
        displayName: "Gemini",
        detail: "Current local source"
    )

    static let all: [GlanceSource] = [openCodeLocal, codexLocal, claudeCodeLocal, geminiCLILocal]
    static let `default`: GlanceSource = openCodeLocal
}
