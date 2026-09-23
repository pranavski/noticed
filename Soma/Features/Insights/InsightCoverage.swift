import Foundation

/// How far the log is from the point where the engine can say anything.
///
/// The empty state used to say "a couple more weeks" to everyone, forever,
/// which is both vague and — once the gate is actually cleared — wrong. The
/// wait has a number, the server already computes it, and someone deciding
/// whether to open the app on day three deserves to see it.
///
/// The thresholds below MIRROR `MIN_MEAL_DAYS` / `MIN_BODY_DAYS` in
/// `supabase/functions/generate-insights/digest.ts`. They are duplicated
/// rather than fetched because the copy has to render before any call is
/// made; `InsightCoverageTests` pins them so the two cannot drift silently.
struct InsightCoverage: Equatable {
    /// Days in the window with at least one meal logged.
    let mealDays: Int
    /// Days with any body signal at all — a HealthKit row or an energy
    /// check-in. Mirrors the `Math.max` over every signal in
    /// `hasSufficientData`: one is enough, they don't add up.
    let bodyDays: Int

    static let requiredMealDays = 7
    static let requiredBodyDays = 7

    var mealDaysRemaining: Int { max(0, Self.requiredMealDays - mealDays) }
    var bodyDaysRemaining: Int { max(0, Self.requiredBodyDays - bodyDays) }

    /// True once the engine will actually run. An empty feed past this point
    /// means the statistics found nothing — a different fact, said differently.
    var isSufficient: Bool { mealDaysRemaining == 0 && bodyDaysRemaining == 0 }

    /// The sentence under "patterns need a little more to go on."
    ///
    /// Names what is short and what is already in, never what the person
    /// failed to do. No target, no streak, no encouragement to catch up.
    var note: String {
        switch (mealDaysRemaining, bodyDaysRemaining) {
        case (0, 0):
            // Past the gate. Silence here is a finding about the data, not a
            // countdown, and saying "keep logging" would misdescribe it.
            return "there's enough to look at now. nothing has held up well "
                 + "enough to be worth showing yet — which is itself an "
                 + "honest answer, not a delay."

        case let (meals, 0) where meals > 0:
            return "\(Self.days(meals)) with a meal logged and the engine has "
                 + "enough to work with. your body signals are already in."

        case let (0, body) where body > 0:
            return "the meals are there. \(Self.days(body)) with a body signal "
                 + "to go — connecting HealthKit (in kitchen) reads the last "
                 + "30 days at once, which usually covers it immediately."

        case let (meals, body):
            return "\(Self.days(meals)) with a meal logged, and \(Self.days(body)) "
                 + "with a body signal. connecting HealthKit (in kitchen) reads "
                 + "the last 30 days at once and often clears the second half "
                 + "on the spot."
        }
    }

    private static func days(_ n: Int) -> String {
        n == 1 ? "1 more day" : "\(n) more days"
    }
}
