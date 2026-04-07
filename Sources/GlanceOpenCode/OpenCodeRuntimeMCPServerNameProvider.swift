import Foundation

public protocol OpenCodeMCPServerNameProviding: Sendable {
    func loadServerNames() async throws -> Set<String>
}

public final class OpenCodeRuntimeMCPServerNameProvider: OpenCodeMCPServerNameProviding {
    private let paths: OpenCodePaths
    private let fetchMCPStatusData: @Sendable (URL) async throws -> Data

    public init(
        paths: OpenCodePaths = .live,
        fetchMCPStatusData: @escaping @Sendable (URL) async throws -> Data = OpenCodeRuntimeMCPServerNameProvider.fetchMCPStatusData
    ) {
        self.paths = paths
        self.fetchMCPStatusData = fetchMCPStatusData
    }

    public func loadServerNames() async throws -> Set<String> {
        if let runtimeNames = try await loadFromDefaultRuntimeServer(), !runtimeNames.isEmpty {
            return runtimeNames
        }

        return try loadFromLogs()
    }

    private func loadFromDefaultRuntimeServer() async throws -> Set<String>? {
        for baseURL in defaultRuntimeBaseURLs {
            let endpoint = baseURL.appending(path: "mcp", directoryHint: .notDirectory)
            do {
                let data = try await fetchMCPStatusData(endpoint)
                let names = try parseServerNames(fromStatusJSON: data)
                if !names.isEmpty {
                    return names
                }
            } catch {
                continue
            }
        }

        return nil
    }

    private func loadFromLogs() throws -> Set<String> {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: paths.logDirectory.path) else {
            return []
        }

        let logFiles = try fileManager.contentsOfDirectory(
            at: paths.logDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "log" }
        .sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        var discovered: Set<String> = []
        for logFile in logFiles.prefix(5) {
            let content = try String(contentsOf: logFile, encoding: .utf8)
            for line in content.split(separator: "\n") {
                guard line.contains("service=mcp"), line.contains(" key=") else { continue }
                guard let key = extractValue(named: "key", from: String(line)), !key.isEmpty else { continue }
                discovered.insert(normalizeServerName(key))
            }
        }

        return discovered
    }

    private func parseServerNames(fromStatusJSON data: Data) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw OpenCodeDataError.unexpectedData("Unexpected /mcp response shape")
        }

        return Set(dictionary.keys.map(normalizeServerName))
    }

    private func extractValue(named name: String, from line: String) -> String? {
        guard let range = line.range(of: "\(name)=") else { return nil }
        let suffix = line[range.upperBound...]
        if let end = suffix.firstIndex(where: { $0 == " " || $0 == "]" || $0 == "," }) {
            return String(suffix[..<end])
        }
        return String(suffix)
    }

    private func normalizeServerName(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)

        let quoteCharacters: Set<Character> = ["\"", "'", "`"]
        while let first = normalized.first, quoteCharacters.contains(first) {
            normalized.removeFirst()
        }

        let trailingJunk: Set<Character> = ["\"", "'", "`", ".", ",", ";", ":", ")", "]", "}"]
        while let last = normalized.last, trailingJunk.contains(last) {
            normalized.removeLast()
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var defaultRuntimeBaseURLs: [URL] {
        [
            URL(string: "http://127.0.0.1:4096")!,
            URL(string: "http://localhost:4096")!,
        ]
    }

    public static func fetchMCPStatusData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw OpenCodeDataError.unexpectedData("Failed to fetch MCP status from \(url.absoluteString)")
        }
        return data
    }
}
