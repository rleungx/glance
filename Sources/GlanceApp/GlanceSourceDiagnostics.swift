import Foundation

enum GlanceSourceReadiness: String, Codable, Equatable {
    case ready
    case needsSetup
    case unavailable
}

enum GlanceSourceArtifactKind: Codable, Hashable {
    case file
    case directory
    case command
}

enum GlanceSourceUsageSupport: String, Codable {
    case observations
    case inventoryOnly
}

struct GlanceSourceArtifact: Identifiable, Hashable, Codable {
    let label: String
    let kind: GlanceSourceArtifactKind
    let displayPath: String
    let isPresent: Bool

    var id: String { label + ":" + displayPath }
}

struct GlanceSourceDiagnostics: Codable, Equatable {
    let readiness: GlanceSourceReadiness
    let supportsRollingWindows: Bool
    let artifacts: [GlanceSourceArtifact]
    let summary: String
    var usageSupport: GlanceSourceUsageSupport = .observations

    var statusLabel: String {
        switch readiness {
        case .ready: return usageSupport == .inventoryOnly ? "Inventory only" : "Ready"
        case .needsSetup: return "Needs setup"
        case .unavailable: return "Unavailable"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case readiness, supportsRollingWindows, artifacts, summary, usageSupport
    }
}

extension GlanceSourceDiagnostics {
    // Older support reports predate inventory-only sources.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        readiness = try values.decode(GlanceSourceReadiness.self, forKey: .readiness)
        supportsRollingWindows = try values.decode(Bool.self, forKey: .supportsRollingWindows)
        artifacts = try values.decode([GlanceSourceArtifact].self, forKey: .artifacts)
        summary = try values.decode(String.self, forKey: .summary)
        usageSupport = try values.decodeIfPresent(GlanceSourceUsageSupport.self, forKey: .usageSupport) ?? .observations
    }
}
