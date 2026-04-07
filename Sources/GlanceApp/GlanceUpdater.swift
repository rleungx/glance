import Combine
import Foundation
import Sparkle

@MainActor
final class GlanceUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    private enum InfoKey {
        static let feedURL = "SUFeedURL"
        static let publicEDKey = "SUPublicEDKey"
        static let environmentFeedURL = "GLANCE_SPARKLE_FEED_URL"
    }

    private enum PlaceholderValue {
        static let feedURL = "https://example.com/appcast.xml"
        static let publicEDKey = "REPLACE_WITH_SPARKLE_PUBLIC_KEY"
    }

    struct Configuration: Equatable {
        let feedURL: URL?
        let publicEDKey: String?

        init(infoDictionary: [String: Any], environment: [String: String] = [:]) {
            let environmentFeedURL = Self.validatedURL(environment[InfoKey.environmentFeedURL])
            let bundleFeedURL = Self.validatedURL(Self.stringValue(in: infoDictionary, forKey: InfoKey.feedURL))
            let publicEDKey = Self.validatedPublicEDKey(Self.stringValue(in: infoDictionary, forKey: InfoKey.publicEDKey))

            self.feedURL = environmentFeedURL ?? bundleFeedURL
            self.publicEDKey = publicEDKey
        }

        var isConfigured: Bool {
            feedURL != nil && publicEDKey != nil
        }

        private static func stringValue(in infoDictionary: [String: Any], forKey key: String) -> String? {
            guard let value = infoDictionary[key] as? String else {
                return nil
            }

            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedValue.isEmpty ? nil : trimmedValue
        }

        private static func validatedURL(_ candidate: String?) -> URL? {
            guard let candidate else {
                return nil
            }

            let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedCandidate != PlaceholderValue.feedURL else {
                return nil
            }
            guard
                let url = URL(string: trimmedCandidate),
                let scheme = url.scheme?.lowercased(),
                scheme == "https",
                url.host != nil
            else {
                return nil
            }

            return url
        }

        private static func validatedPublicEDKey(_ candidate: String?) -> String? {
            guard let candidate else {
                return nil
            }

            let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCandidate.isEmpty, trimmedCandidate != PlaceholderValue.publicEDKey else {
                return nil
            }

            return trimmedCandidate
        }
    }

    @Published private(set) var canCheckForUpdates = false

    private let configuration: Configuration
    private var updaterController: SPUStandardUpdaterController?
    private var cancellables: Set<AnyCancellable> = []

    init(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.configuration = Configuration(infoDictionary: bundle.infoDictionary ?? [:], environment: environment)
        super.init()

        guard configuration.isConfigured else {
            return
        }

        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.updaterController = controller
        self.canCheckForUpdates = controller.updater.canCheckForUpdates

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        configuration.feedURL?.absoluteString
    }
}
