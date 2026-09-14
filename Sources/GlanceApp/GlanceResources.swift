import Foundation

enum GlanceResources {
    static func packagedBundle(in appBundle: Bundle = .main) -> Bundle? {
        guard let url = appBundle.resourceURL?.appendingPathComponent("Glance_GlanceApp.bundle") else {
            return nil
        }
        return Bundle(url: url)
    }

    // Check the app's Resources directory before evaluating SwiftPM's accessor,
    // which traps when neither the build directory nor its CLI layout exists.
    static var bundle: Bundle { packagedBundle() ?? Bundle.module }
}
