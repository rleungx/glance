import Foundation

public struct GeminiInstalledSkill: Hashable, Sendable {
    public let name: String
    public let enabled: Bool
    public let builtIn: Bool
    public let location: String?

    public init(name: String, enabled: Bool, builtIn: Bool, location: String?) {
        self.name = name
        self.enabled = enabled
        self.builtIn = builtIn
        self.location = location
    }
}

public struct GeminiConfiguredMCPServer: Hashable, Sendable {
    public let name: String
    public let enabled: Bool

    public init(name: String, enabled: Bool) {
        self.name = name
        self.enabled = enabled
    }
}

public enum GeminiToolStatus: String, Sendable {
    case success
    case error
    case unknown
}

extension GeminiToolStatus: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self))?.lowercased() ?? ""
        self = GeminiToolStatus(rawValue: rawValue) ?? .unknown
    }
}

public struct GeminiObservedToolEvent: Sendable {
    public let timestamp: Date
    public let toolName: String
    public let args: [String: GeminiJSONValue]
    public let status: GeminiToolStatus?

    public init(timestamp: Date, toolName: String, args: [String: GeminiJSONValue], status: GeminiToolStatus?) {
        self.timestamp = timestamp
        self.toolName = toolName
        self.args = args
        self.status = status
    }
}

public struct GeminiTranscriptLoadResult: Sendable {
    public let events: [GeminiObservedToolEvent]
    public let skippedFilesCount: Int

    public init(events: [GeminiObservedToolEvent], skippedFilesCount: Int) {
        self.events = events
        self.skippedFilesCount = skippedFilesCount
    }
}

public enum GeminiJSONValue: Decodable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: GeminiJSONValue])
    case array([GeminiJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([String: GeminiJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([GeminiJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.typeMismatch(GeminiJSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
        }
    }

    public var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }
}

public enum GeminiDataError: LocalizedError {
    case commandFailed(String)
    case invalidSession(URL)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            return "Gemini command failed: \(message)"
        case let .invalidSession(url):
            return "Invalid Gemini session file: \(url.path)"
        }
    }
}
