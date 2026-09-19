import XCTest
@testable import Soma

/// The free tier is a promise made in the App Store description, on the
/// paywall, and in the privacy policy: if you stop paying, nothing is taken
/// away. These tests are that promise written as code — a gate added in the
/// wrong place later should fail here rather than ship.
final class SubscriptionStateTests: XCTestCase {

    private let allStates: [SubscriptionState] = [
        .free,
        .trial(expires: Date(timeIntervalSince1970: 2_000_000_000)),
        .trial(expires: nil),
        .subscribed(expires: Date(timeIntervalSince1970: 2_000_000_000)),
        .subscribed(expires: nil),
    ]

    /// The whole free tier, in one assertion per promise.
    func testTheRecordIsNeverGated() {
        for state in allStates {
            XCTAssertTrue(state.canLogMeals, "\(state)")
            XCTAssertTrue(state.canReadOwnRecord, "\(state)")
            XCTAssertTrue(state.canExport, "\(state)")
            XCTAssertTrue(state.canSeeReflections, "\(state)")
            XCTAssertTrue(state.canReadExistingInsights, "\(state)")
        }
    }

    /// Reflections are pure server-side templating with no model call behind
    /// them, so there is no cost argument for ever gating them. If someone
    /// later wants to, this test is where that argument has to be had.
    func testReflectionsStayFreeEvenWhenLapsed() {
        XCTAssertTrue(SubscriptionState.free.canSeeReflections)
    }

    /// Findings already shown were true when written and belong to the
    /// reader. Lapsing declines further work; it does not take back work
    /// already done.
    func testExistingFindingsSurviveALapse() {
        XCTAssertTrue(SubscriptionState.free.canReadExistingInsights)
    }

    /// What a subscription actually buys: new findings, and the reading of a
    /// meal into ingredients that feeds them.
    /// `docs/decisions/2026-09-19-subscription-enforcement.md` §1–§2.
    func testGenerationAndParsingArePaid() {
        XCTAssertFalse(SubscriptionState.free.canGenerateInsights)
        XCTAssertTrue(SubscriptionState.trial(expires: nil).canGenerateInsights)
        XCTAssertTrue(SubscriptionState.subscribed(expires: nil).canGenerateInsights)

        XCTAssertFalse(SubscriptionState.free.canParseMeals)
        XCTAssertTrue(SubscriptionState.trial(expires: nil).canParseMeals)
        XCTAssertTrue(SubscriptionState.subscribed(expires: nil).canParseMeals)
    }

    /// Parsing moved to the paid side on 2026-09-19, and logging did not go
    /// with it. A free account files every meal in its own words — the
    /// distinction the whole free tier rests on, and the one a future
    /// "simplification" is most likely to erase.
    func testLoggingStaysFreeEvenThoughParsingIsNot() {
        XCTAssertTrue(SubscriptionState.free.canLogMeals)
        XCTAssertFalse(SubscriptionState.free.canParseMeals)
    }

    /// A trial is a full entitlement while it lasts — a trialist who hits the
    /// coverage gate on day nine must get their first finding, which is the
    /// entire reason the trial is 14 days and not 7. It must also be parsing
    /// their meals throughout, or there is nothing for the gate to measure.
    func testTrialIsAFullEntitlement() {
        let trial = SubscriptionState.trial(expires: nil)
        let paid = SubscriptionState.subscribed(expires: nil)
        XCTAssertEqual(trial.canGenerateInsights, paid.canGenerateInsights)
        XCTAssertEqual(trial.canParseMeals, paid.canParseMeals)
    }

    /// Guideline 3.1.2: the paywall has to carry a **functional** link to
    /// the terms of use (EULA) alongside the price and the period.
    /// `SubscribeSheet` renders that link only when the URL parses, so a
    /// typo would drop it silently and the first sign of it would be a
    /// rejection rather than a red test.
    func testPaywallCarriesTermsAndPrivacyLinks() throws {
        let terms = try XCTUnwrap(SomaFeatures.termsOfUseURL)
        XCTAssertEqual(terms.scheme, "https", "the terms link must not be insecure")

        // The paywall's privacy link opens the in-app policy, which needs no
        // network — but that sheet offers the hosted copy too, and only when
        // this flag says it resolves.
        let privacy = try XCTUnwrap(SomaFeatures.privacyPolicyURL)
        XCTAssertEqual(privacy.scheme, "https")
        XCTAssertTrue(SomaFeatures.privacyPolicyIsHosted)
    }

    func testProductIDMatchesTheStoreKitConfiguration() throws {
        // Noticed.storekit is what the simulator sells; App Store Connect
        // must agree with both. A silent mismatch means an empty paywall.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SomaTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Noticed.storekit")
        let data = try Data(contentsOf: url)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(
            text.contains(SubscriptionStore.yearlyProductID),
            "Noticed.storekit does not define \(SubscriptionStore.yearlyProductID)"
        )
        // The 14-day trial decided in the positioning record, not 7 — a
        // 7-day trial expires before a realistic user reaches the gate.
        XCTAssertTrue(text.contains("\"P2W\""), "introductory offer is not two weeks")
        XCTAssertTrue(text.contains("\"free\""), "introductory offer is not a free trial")
        XCTAssertTrue(text.contains("\"P1Y\""), "subscription is not yearly")
    }
}
