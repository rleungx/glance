import Foundation
import GlanceCore

public struct InstalledSkill: Hashable, Sendable {
    public let name: String
    public let directory: URL

    public init(name: String, directory: URL) {
        self.name = name
        self.directory = directory
    }
}

public struct ConfiguredMCPServer: Hashable, Sendable {
    public let name: String
    public let enabled: Bool

    public init(name: String, enabled: Bool) {
        self.name = name
        self.enabled = enabled
    }
}

public struct ObservedCapabilityUsage: Sendable {
    public let usage: CapabilityUsage
    public let serverName: String?

    public init(usage: CapabilityUsage, serverName: String? = nil) {
        self.usage = usage
        self.serverName = serverName
    }
}

public enum OpenCodeDataError: LocalizedError {
    case missingFile(URL)
    case invalidConfig(URL)
    case sqlite(String)
    case unexpectedData(String)

    public var errorDescription: String? {
        switch self {
        case let .missingFile(url):
            return "Missing file: \(url.path)"
        case let .invalidConfig(url):
            return "Invalid config: \(url.path)"
        case let .sqlite(message):
            return "SQLite error: \(message)"
        case let .unexpectedData(message):
            return "Unexpected OpenCode data: \(message)"
        }
    }
}
