import Foundation

public struct GeminiExecutableLocator: Sendable {
    private enum EnvironmentKey {
        static let executablePath = "GLANCE_GEMINI_EXECUTABLE"
        static let path = "PATH"
    }

    private let homeDirectory: URL
    private let environment: [String: String]

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    public func executableURL() -> URL? {
        for candidate in candidates() {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public func isInstalled() -> Bool {
        executableURL() != nil
    }

    /// GUI applications do not inherit the user's interactive shell PATH.
    public func processEnvironment(for executableURL: URL) -> [String: String] {
        var result = environment
        let inheritedPaths = (environment[EnvironmentKey.path] ?? "").split(separator: ":").map(String.init)
        let runtimePaths = [
            executableURL.deletingLastPathComponent().path,
            executableURL.resolvingSymlinksInPath().deletingLastPathComponent().path,
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        var seen = Set<String>()
        result[EnvironmentKey.path] = (inheritedPaths + runtimePaths)
            .filter { $0.hasPrefix("/") && seen.insert($0).inserted }
            .joined(separator: ":")
        return result
    }

    private func candidates() -> [URL] {
        var urls: [URL] = []

        if let override = environment[EnvironmentKey.executablePath]?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            urls.append(expandedURL(from: override))
        }

        let pathEntries = (environment[EnvironmentKey.path] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty && $0.hasPrefix("/") }

        urls.append(contentsOf: pathEntries.map { URL(fileURLWithPath: $0).appendingPathComponent("gemini") })
        urls.append(contentsOf: [
            homeDirectory.appending(path: "bin/gemini", directoryHint: .notDirectory),
            URL(fileURLWithPath: "/opt/homebrew/bin/gemini"),
            URL(fileURLWithPath: "/usr/local/bin/gemini"),
            URL(fileURLWithPath: "/usr/bin/gemini"),
        ])

        var seen: Set<String> = []
        return urls.filter { seen.insert($0.path).inserted }
    }

    private func expandedURL(from path: String) -> URL {
        if path.hasPrefix("~/") {
            let relativePath = String(path.dropFirst(2))
            return homeDirectory.appending(path: relativePath, directoryHint: .notDirectory)
        }
        return URL(fileURLWithPath: path)
    }
}
