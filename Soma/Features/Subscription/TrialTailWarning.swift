import Foundation

/// Tells a trialist, before the charge lands, that they are still short of
/// the gate.
///
/// The trial is 14 days because a realistic user clears the coverage gate
/// around calendar day 9–12. The tail is the problem this type exists for: a
/// sporadic logger reaches day 14 having seen nothing at all, and is charged
/// for a feature they have never once received. `InsightCoverage` already
/// knows, on-device, exactly how short they are — so there is no excuse for
/// letting that charge arrive unannounced.
///
/// `docs/decisions/2026-09-19-subscription-enforcement.md` §4.
///
/// Deliberately not a nudge to log more. It names the gap and points at the
/// cancel path; whether the reader wants to close the gap or stop paying is
/// theirs to decide, and an app that says "log three more days to get your
/// money's worth" has turned into the thing this one refuses to be.
enum TrialTailWarning {

    /// How close to the end of the trial the notice appears. Four days puts
    /// it at roughly day eleven of fourteen — late enough that a normal
    /// logger has already cleared the gate and never sees it, early enough
    /// that cancelling is unhurried.
    static let noticeWindowDays = 4

    /// The sentence to show, or nil when there is nothing honest to say:
    /// not on trial, no expiry date, still outside the window, already past
    /// the gate, or coverage not loaded yet. A missing coverage read is
    /// silence rather than a guess — warning someone off a charge on data we
    /// do not have would be its own kind of lie.
    static func note(
        state: SubscriptionState,
        coverage: InsightCoverage?,
        now: Date = Date()
    ) -> String? {
        guard case .trial(let expires) = state, let expires else { return nil }
        guard let coverage, !coverage.isSufficient else { return nil }
        // An expiry already behind us is a trial that ended, not a charge
        // about to land. StoreKit drops expired entitlements before this
        // type ever sees them, but saying "ends today" about a date in the
        // past would be a lie even in a state we think is unreachable.
        guard expires > now else { return nil }

        let daysLeft = daysUntil(expires, from: now)
        guard daysLeft <= noticeWindowDays else { return nil }

        return "\(ending(in: daysLeft)), and \(shortfall(coverage)). if you'd "
             + "rather not be charged for something you haven't seen yet, you "
             + "can cancel in the App Store — everything you've written down "
             + "stays yours either way."
    }

    /// Whole days remaining, rounded up: a trial with six hours left has one
    /// day left, not zero. Callers guarantee a future date.
    private static func daysUntil(_ expires: Date, from now: Date) -> Int {
        Int(ceil(expires.timeIntervalSince(now) / 86_400))
    }

    private static func ending(in days: Int) -> String {
        switch days {
        case 0:  return "your trial ends today"
        case 1:  return "your trial ends tomorrow"
        default: return "your trial ends in \(days) days"
        }
    }

    /// What is actually missing, in the same terms the empty state uses.
    private static func shortfall(_ coverage: InsightCoverage) -> String {
        let meals = coverage.mealDaysRemaining
        let body = coverage.bodyDaysRemaining
        switch (meals, body) {
        case let (m, 0) where m > 0:
            return "the first look is still \(days(m)) with a meal logged away"
        case let (0, b) where b > 0:
            return "the first look is still \(days(b)) with a body signal away "
                 + "— connecting HealthKit in the kitchen usually clears that "
                 + "on the spot"
        case let (m, b):
            return "the first look is still \(days(m)) with a meal logged and "
                 + "\(days(b)) with a body signal away"
        }
    }

    private static func days(_ n: Int) -> String {
        n == 1 ? "a day" : "\(n) days"
    }
}
