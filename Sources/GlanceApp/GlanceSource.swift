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
        case "antigravity-local":
            return "sparkles"
        case "devin-local":
            return "terminal"
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

    static let antigravityLocal = GlanceSource(
        id: "antigravity-local",
        displayName: "Antigravity",
        detail: "Skill inventory only · App & IDE"
    )

    static let devinCLILocal = GlanceSource(
        id: "devin-local",
        displayName: "Devin CLI",
        detail: "Skill inventory only · Includes Fusion"
    )

    static let all: [GlanceSource] = [openCodeLocal, codexLocal, claudeCodeLocal, antigravityLocal, devinCLILocal]
    static let `default`: GlanceSource = openCodeLocal
}
