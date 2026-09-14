import Foundation

public protocol GeminiCommandRunning: Sendable {
    func run(arguments: [String]) throws -> String
}

public struct GeminiProcessRunner: GeminiCommandRunning {
    private let executableLocator: GeminiExecutableLocator

    public init(executableLocator: GeminiExecutableLocator = GeminiExecutableLocator()) {
        self.executableLocator = executableLocator
    }

    public func run(arguments: [String]) throws -> String {
        guard let executableURL = executableLocator.executableURL() else {
            throw GeminiDataError.commandFailed("Gemini executable was not found. Set GLANCE_GEMINI_EXECUTABLE or install gemini in a standard location.")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = executableLocator.processEnvironment(for: executableURL)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdoutCollector = OutputCollector(fileHandle: stdout.fileHandleForReading)
        let stderrCollector = OutputCollector(fileHandle: stderr.fileHandleForReading)

        try process.run()
        stdoutCollector.start()
        stderrCollector.start()
        process.waitUntilExit()

        let output = stdoutCollector.finish()
        let errorOutput = stderrCollector.finish()
        return try Self.result(output: output, errorOutput: errorOutput, terminationStatus: process.terminationStatus)
    }

    static func result(output: String, errorOutput: String, terminationStatus: Int32) throws -> String {
        guard terminationStatus == 0 else {
            throw GeminiDataError.commandFailed(errorOutput.isEmpty ? output : errorOutput)
        }

        return output
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let lock = NSLock()
    private var data = Data()

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func start() {
        fileHandle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.append(chunk)
        }
    }

    func finish() -> String {
        fileHandle.readabilityHandler = nil
        let trailingData = fileHandle.readDataToEndOfFile()
        if !trailingData.isEmpty {
            append(trailingData)
        }
        return String(data: snapshot(), encoding: .utf8) ?? ""
    }

    private func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    private func snapshot() -> Data {
        lock.lock()
        let copy = data
        lock.unlock()
        return copy
    }
}
