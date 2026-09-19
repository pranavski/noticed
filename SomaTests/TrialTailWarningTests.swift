import XCTest
@testable import Soma

/// The promise here is the one in
/// `docs/decisions/2026-09-19-subscription-enforcement.md` §4: nobody is
/// charged $15 for a feature they have never once received without being
/// told first. These tests are the cases where saying nothing would be the
/// failure, and the cases where saying something would be a lie.
final class TrialTailWarningTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func inDays(_ days: Double) -> Date {
        now.addingTimeInterval(days * 86_400)
    }

    private let short = InsightCoverage(mealDays: 4, bodyDays: 30)
    private let cleared = InsightCoverage(mealDays: 7, bodyDays: 7)

    /// The whole point: three days out, still short, say so.
    func testWarnsInsideTheWindowWhenStillShort() throws {
        let note = try XCTUnwrap(TrialTailWarning.note(
            state: .trial(expires: inDays(3)), coverage: short, now: now
        ))
        XCTAssertTrue(note.contains("ends in 3 days"), note)
        XCTAssertTrue(note.contains("3 days with a meal logged"), note)
        XCTAssertTrue(note.contains("cancel"), note)
    }

    /// A trialist who has cleared the gate is getting what they paid for.
    /// Warning them off would be scaremongering, not honesty.
    func testSilentOncePastTheGate() {
        XCTAssertNil(TrialTailWarning.note(
            state: .trial(expires: inDays(3)), coverage: cleared, now: now
        ))
    }

    /// Day one of fourteen is not the moment to talk about cancelling.
    func testSilentEarlyInTheTrial() {
        XCTAssertNil(TrialTailWarning.note(
            state: .trial(expires: inDays(13)), coverage: short, now: now
        ))
    }

    /// Coverage we haven't loaded is not coverage we can describe. Silence
    /// beats a guess about someone's money.
    func testSilentWhenCoverageIsUnknown() {
        XCTAssertNil(TrialTailWarning.note(
            state: .trial(expires: inDays(2)), coverage: nil, now: now
        ))
    }

    /// Only trialists face the surprise charge this exists to prevent.
    func testSilentForEveryNonTrialState() {
        for state in [
            SubscriptionState.free,
            .subscribed(expires: inDays(2)),
            .subscribed(expires: nil),
            .trial(expires: nil),
        ] {
            XCTAssertNil(
                TrialTailWarning.note(state: state, coverage: short, now: now),
                "\(state)"
            )
        }
    }

    /// Hours, not days, left. Rounding down would say "ends today" on a
    /// trial with a night still to run, and rounding to zero would drop the
    /// notice entirely on the last day — the day it matters most.
    func testPartialDaysRoundUp() throws {
        let note = try XCTUnwrap(TrialTailWarning.note(
            state: .trial(expires: inDays(0.25)), coverage: short, now: now
        ))
        XCTAssertTrue(note.contains("ends tomorrow"), note)
    }

    /// An expiry already behind us is a lapsed trial, not a pending charge.
    func testSilentAfterExpiry() {
        XCTAssertNil(TrialTailWarning.note(
            state: .trial(expires: inDays(-1)), coverage: short, now: now
        ))
    }

    /// The body-signal shortfall names the thing that fixes it, since one
    /// HealthKit connection usually clears thirty days at once.
    func testBodySignalShortfallPointsAtHealthKit() throws {
        let note = try XCTUnwrap(TrialTailWarning.note(
            state: .trial(expires: inDays(1)),
            coverage: InsightCoverage(mealDays: 20, bodyDays: 2),
            now: now
        ))
        XCTAssertTrue(note.contains("HealthKit"), note)
    }

    /// It names the gap and the cancel path, and stops. No "log more", no
    /// target, no encouragement to catch up — see the type's note.
    func testItNeverTellsThemToLogMore() throws {
        let note = try XCTUnwrap(TrialTailWarning.note(
            state: .trial(expires: inDays(2)), coverage: short, now: now
        ))
        for nudge in ["log more", "keep logging", "you should", "don't forget"] {
            XCTAssertFalse(note.localizedCaseInsensitiveContains(nudge), note)
        }
    }
}
