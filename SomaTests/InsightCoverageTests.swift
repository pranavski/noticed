import XCTest
@testable import Soma

/// The empty-state countdown restates a server-side gate. These tests exist
/// to make the restatement fail loudly if the gate moves.
final class InsightCoverageTests: XCTestCase {

    /// Mirrors `MIN_MEAL_DAYS` / `MIN_BODY_DAYS` in
    /// `supabase/functions/generate-insights/digest.ts`. If that file changes,
    /// this test is the thing that is supposed to break.
    func testThresholdsMatchTheEngine() {
        XCTAssertEqual(InsightCoverage.requiredMealDays, 7)
        XCTAssertEqual(InsightCoverage.requiredBodyDays, 7)
        XCTAssertEqual(InsightCoverageRepository.windowDays, 30)
    }

    func testSufficiencyMatchesBothHalves() {
        XCTAssertTrue(InsightCoverage(mealDays: 7, bodyDays: 7).isSufficient)
        XCTAssertTrue(InsightCoverage(mealDays: 30, bodyDays: 30).isSufficient)
        // Either half short is short — the gate is an AND, as in the engine.
        XCTAssertFalse(InsightCoverage(mealDays: 6, bodyDays: 30).isSufficient)
        XCTAssertFalse(InsightCoverage(mealDays: 30, bodyDays: 6).isSufficient)
    }

    func testRemainingNeverGoesNegative() {
        let past = InsightCoverage(mealDays: 20, bodyDays: 30)
        XCTAssertEqual(past.mealDaysRemaining, 0)
        XCTAssertEqual(past.bodyDaysRemaining, 0)
    }

    /// The common case: HealthKit connected (30 days backfilled on connect),
    /// a few days of meals logged. Only the meal half should be counted out.
    func testNoteCountsOnlyTheHalfThatIsShort() {
        let note = InsightCoverage(mealDays: 5, bodyDays: 30).note
        XCTAssertTrue(note.contains("2 more days"), note)
        XCTAssertFalse(note.contains("HealthKit"), note)
    }

    func testNoteOffersHealthKitWhenBodySignalsAreMissing() {
        let note = InsightCoverage(mealDays: 7, bodyDays: 2).note
        XCTAssertTrue(note.contains("5 more days"), note)
        XCTAssertTrue(note.contains("HealthKit"), note)
    }

    func testNoteSingularisesTheLastDay() {
        XCTAssertTrue(InsightCoverage(mealDays: 6, bodyDays: 30).note.contains("1 more day"))
        XCTAssertFalse(InsightCoverage(mealDays: 6, bodyDays: 30).note.contains("1 more days"))
    }

    /// Past the gate the copy must stop counting and start reporting. An
    /// empty feed here means the statistics found nothing, and saying "keep
    /// logging" would misdescribe a real result as a delay.
    func testNotePastTheGateIsAResultNotACountdown() {
        let note = InsightCoverage(mealDays: 14, bodyDays: 14).note
        XCTAssertFalse(note.contains("more days"), note)
        XCTAssertTrue(note.contains("honest answer"), note)
    }

    /// Never prescriptive, never a target, never shaming — the same rule the
    /// insight copy is held to.
    func testNoteAvoidsImperativesAndTargets() {
        let banned = ["should", "must", "aim for", "try to", "goal", "target", "streak"]
        for meals in 0...8 {
            for body in 0...8 {
                let note = InsightCoverage(mealDays: meals, bodyDays: body).note.lowercased()
                for word in banned {
                    XCTAssertFalse(note.contains(word), "\"\(word)\" in: \(note)")
                }
            }
        }
    }
}
