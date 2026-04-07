import AppKit
import Foundation

public struct GlanceAppMetadata: Equatable, Sendable {
    public static let productName = "Glance"

    private enum InfoKey {
        static let bundleDisplayName = "CFBundleDisplayName"
        static let bundleName = "CFBundleName"
        static let shortVersion = "CFBundleShortVersionString"
        static let buildVersion = "CFBundleVersion"
    }

    public let applicationName: String
    public let shortVersion: String?
    public let buildVersion: String?

    public init(bundle: Bundle = .main, environment _: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(
            infoDictionary: bundle.infoDictionary ?? [:],
            bundleURL: bundle.bundleURL
        )
    }

    public init(infoDictionary: [String: Any], bundleURL: URL? = nil) {
        applicationName = Self.stringValue(in: infoDictionary, forKey: InfoKey.bundleDisplayName)
            ?? Self.stringValue(in: infoDictionary, forKey: InfoKey.bundleName)
            ?? bundleURL?.deletingPathExtension().lastPathComponent
            ?? Self.productName
        shortVersion = Self.stringValue(in: infoDictionary, forKey: InfoKey.shortVersion)
        buildVersion = Self.stringValue(in: infoDictionary, forKey: InfoKey.buildVersion)
    }

    public var aboutMenuTitle: String {
        "About \(Self.productName)"
    }

    public var versionDescription: String {
        shortVersion ?? buildVersion ?? "debug"
    }

    public var versionLine: String {
        "Version \(versionDescription)"
    }

    @MainActor
    public func showAboutPanel(application: NSApplication = .shared) {
        application.activate(ignoringOtherApps: true)
        application.orderFrontStandardAboutPanel(nil)
    }

    private static func stringValue(in infoDictionary: [String: Any], forKey key: String) -> String? {
        guard let value = infoDictionary[key] as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
