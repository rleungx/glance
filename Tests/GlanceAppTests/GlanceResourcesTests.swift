import Foundation
import Testing
@testable import GlanceApp

@Test
func resourcesResolveInsideRelocatedAppBundle() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let appURL = root.appendingPathComponent("Glance.app")
    let resourceURL = appURL.appendingPathComponent("Contents/Resources/Glance_GlanceApp.bundle")
    try FileManager.default.createDirectory(at: resourceURL, withIntermediateDirectories: true)
    let plist: [String: String] = ["CFBundleIdentifier": "test.glance.resources", "CFBundlePackageType": "APPL", "CFBundleExecutable": "Glance"]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: appURL.appendingPathComponent("Contents/Info.plist"))
    try Data([1, 2, 3]).write(to: resourceURL.appendingPathComponent("opencode.png"))
    let app = try #require(Bundle(url: appURL))
    let bundle = try #require(GlanceResources.packagedBundle(in: app))
    #expect(bundle.bundleURL.standardizedFileURL == resourceURL.standardizedFileURL)
    #expect(bundle.url(forResource: "opencode", withExtension: "png") != nil)
}
