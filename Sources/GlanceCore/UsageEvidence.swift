import Foundation
import CryptoKit

/// `observed` means the available files were read, not that all activity was logged.
public enum UsageCompleteness: String, Codable, Sendable {
    case unavailable, partial, observed, verified
}

public struct UsageEvidence: Codable, Equatable, Sendable {
    public var completeness: UsageCompleteness
    public var sources: [String]
    public var filesRead: Int
    public var skippedFiles: Int
    public var skippedRecords: Int
    public var duplicates: Int
    public var inferredIdentities: Int
    public var unmatchedRecords: Int
    public var observedFrom: Date?
    public var observedThrough: Date?
    /// Only an authoritative coverage contract may set these, never first/last event dates.
    public var verifiedFrom: Date?
    public var verifiedThrough: Date?

    public init(completeness: UsageCompleteness = .unavailable, sources: [String] = [], filesRead: Int = 0,
                skippedFiles: Int = 0, skippedRecords: Int = 0, duplicates: Int = 0, inferredIdentities: Int = 0,
                unmatchedRecords: Int = 0, observedFrom: Date? = nil, observedThrough: Date? = nil,
                verifiedFrom: Date? = nil, verifiedThrough: Date? = nil) {
        self.completeness = completeness
        self.sources = sources
        self.filesRead = filesRead
        self.skippedFiles = skippedFiles
        self.skippedRecords = skippedRecords
        self.duplicates = duplicates
        self.inferredIdentities = inferredIdentities
        self.unmatchedRecords = unmatchedRecords
        self.observedFrom = observedFrom
        self.observedThrough = observedThrough
        self.verifiedFrom = verifiedFrom
        self.verifiedThrough = verifiedThrough
    }

    public mutating func finish(timestamps: [Date]) {
        observedFrom = timestamps.min()
        observedThrough = timestamps.max()
        completeness = skippedFiles > 0 || skippedRecords > 0 || unmatchedRecords > 0 ? .partial : (filesRead > 0 ? .observed : .unavailable)
    }

    public func covers(since start: Date, through end: Date) -> Bool {
        guard completeness == .verified, skippedFiles == 0, skippedRecords == 0, inferredIdentities == 0, unmatchedRecords == 0,
              let verifiedFrom, let verifiedThrough else { return false }
        return verifiedFrom <= start && verifiedThrough >= end
    }

    public var summary: String {
        switch completeness {
        case .unavailable: return "Usage data unavailable. Cleanup suggestions are paused."
        case .partial: return "Incomplete usage data: \(skippedFiles) unreadable files, \(skippedRecords) unparsed records, \(unmatchedRecords) records outside known inventory. Cleanup suggestions are paused."
        case .observed: return "Observed local records only; history coverage is unverified. Cleanup suggestions are paused."
        case .verified: return "Usage coverage verified for the reported interval."
        }
    }
}

public struct UsageLoadResult: Sendable {
    public let windows: [RollingWindow: [CapabilityUsage]]
    public let evidence: UsageEvidence
    public let warnings: [String]

    public init(windows: [RollingWindow: [CapabilityUsage]], evidence: UsageEvidence, warnings: [String] = []) {
        self.windows = windows
        self.evidence = evidence
        self.warnings = warnings
    }
}

/// Local-only provenance; never include transcript text or tool arguments.
public struct UsageRecordReference: Codable, Hashable, Sendable {
    public let file: String
    public let record: String
    public init(file: String, record: String) { self.file = file; self.record = record }
}

public enum TranscriptFiles {
    public static func discover(in roots: [URL], extensions: Set<String>, fileManager: FileManager = .default) -> (files: [URL], errors: Int) {
        var errors = 0
        var files: [URL] = []
        for root in roots {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: root.resolvingSymlinksInPath().path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory else { errors += 1; continue }
            } catch {
                let error = error as NSError
                if error.domain != NSCocoaErrorDomain || ![NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { errors += 1 }
                continue
            }
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles], errorHandler: { _, _ in errors += 1; return true }) else {
                errors += 1
                continue
            }
            for case let file as URL in enumerator where extensions.contains(file.pathExtension) {
                do {
                    if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { files.append(file) }
                } catch { errors += 1 }
            }
        }
        return (Array(Set(files)).sorted { $0.path < $1.path }, errors)
    }
}

public enum UsageEventIdentity {
    public static func fingerprint(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func fingerprint(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]) else { return "invalid" }
        return fingerprint(data: data)
    }
}
