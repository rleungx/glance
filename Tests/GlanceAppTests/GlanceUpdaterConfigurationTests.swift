import Foundation
import Testing
@testable import GlanceApp

@Test
func glanceUpdaterConfigurationPrefersEnvironmentFeedURL() {
    let configuration = GlanceUpdater.Configuration(
        infoDictionary: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "public-key",
        ],
        environment: [
            "GLANCE_SPARKLE_FEED_URL": "https://staging.example.com/appcast.xml",
        ]
    )

    #expect(configuration.feedURL == URL(string: "https://staging.example.com/appcast.xml"))
    #expect(configuration.publicEDKey == "public-key")
    #expect(configuration.isConfigured)
}

@Test
func glanceUpdaterConfigurationRequiresPublicKey() {
    let configuration = GlanceUpdater.Configuration(
        infoDictionary: [
            "SUFeedURL": "https://updates.example.org/appcast.xml",
        ]
    )

    #expect(configuration.feedURL == URL(string: "https://updates.example.org/appcast.xml"))
    #expect(configuration.publicEDKey == nil)
    #expect(!configuration.isConfigured)
}

@Test
func glanceUpdaterConfigurationRejectsPlaceholderValues() {
    let configuration = GlanceUpdater.Configuration(
        infoDictionary: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "REPLACE_WITH_SPARKLE_PUBLIC_KEY",
        ]
    )

    #expect(configuration.feedURL == nil)
    #expect(configuration.publicEDKey == nil)
    #expect(!configuration.isConfigured)
}

@Test
func glanceUpdaterConfigurationRejectsInvalidFeedURL() {
    let configuration = GlanceUpdater.Configuration(
        infoDictionary: [
            "SUFeedURL": "not a valid url",
            "SUPublicEDKey": "public-key",
        ]
    )

    #expect(configuration.feedURL == nil)
    #expect(!configuration.isConfigured)
}

@Test
func glanceUpdaterConfigurationRequiresHttpsFeedURL() {
    let configuration = GlanceUpdater.Configuration(
        infoDictionary: [
            "SUFeedURL": "http://example.com/appcast.xml",
            "SUPublicEDKey": "public-key",
        ]
    )

    #expect(configuration.feedURL == nil)
    #expect(!configuration.isConfigured)
}

@Test
func glanceUpdaterConfigurationFallsBackToBundleFeedWhenEnvironmentFeedIsInvalid() {
    let configuration = GlanceUpdater.Configuration(
        infoDictionary: [
            "SUFeedURL": "https://updates.example.org/appcast.xml",
            "SUPublicEDKey": "public-key",
        ],
        environment: [
            "GLANCE_SPARKLE_FEED_URL": "not a valid url",
        ]
    )

    #expect(configuration.feedURL == URL(string: "https://updates.example.org/appcast.xml"))
    #expect(configuration.isConfigured)
}
