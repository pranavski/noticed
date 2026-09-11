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

    /// The one thing a subscription actually buys.
    func testOnlyGenerationIsPaid() {
        XCTAssertFalse(SubscriptionState.free.canGenerateInsights)
        XCTAssertTrue(SubscriptionState.trial(expires: nil).canGenerateInsights)
        XCTAssertTrue(SubscriptionState.subscribed(expires: nil).canGenerateInsights)
    }

    /// A trial is a full entitlement while it lasts — a trialist who hits the
    /// coverage gate on day nine must get their first finding, which is the
    /// entire reason the trial is 14 days and not 7.
    func testTrialIsAFullEntitlement() {
        let trial = SubscriptionState.trial(expires: nil)
        XCTAssertEqual(trial.canGenerateInsights, SubscriptionState.subscribed(expires: nil).canGenerateInsights)
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
