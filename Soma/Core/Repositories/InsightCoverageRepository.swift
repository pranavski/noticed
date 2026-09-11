import Foundation
import Supabase

/// Counts the days behind the insight gate, so the Noticed tab can say how
/// much is left instead of "a couple more weeks".
///
/// Three narrow reads of the caller's own rows over the same 30-day window
/// `generate-insights` uses. Only the date columns are selected — at one row
/// per meal this is a few hundred short strings at worst, and distinctness
/// has to be computed over real rows rather than a `count`.
struct InsightCoverageRepository {
    private let client: SupabaseClient

    /// Matches `WINDOW_DAYS` in `generate-insights/candidates.ts`.
    static let windowDays = 30

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    private struct DayRow: Decodable { let day: String }

    func fetchCoverage(now: Date = Date()) async throws -> InsightCoverage {
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -Self.windowDays, to: now
        ) ?? now
        let since = SupabaseDates.localDay(cutoff)
        let decoder = JSONDecoder()

        // `eaten_date` is the user's local date, written by the client; the
        // insight engine prefers it over `eaten_at` for exactly this reason.
        async let mealsData = client
            .from("meals")
            .select("eaten_date")
            .gte("eaten_date", value: since)
            .execute()

        // A health_days row only exists for a day that had some signal —
        // all-nil days are skipped at sync time — so presence is the count.
        async let healthData = client
            .from("health_days")
            .select("day")
            .gte("day", value: since)
            .execute()

        async let checkinData = client
            .from("daily_checkins")
            .select("check_date")
            .gte("check_date", value: since)
            .execute()

        let (meals, health, checkins) = try await (mealsData, healthData, checkinData)

        let mealDays = try Self.distinctDays(meals.data, key: "eaten_date", decoder: decoder)
        let healthDays = try Self.distinctDays(health.data, key: "day", decoder: decoder)
        let checkinDays = try Self.distinctDays(checkins.data, key: "check_date", decoder: decoder)

        return InsightCoverage(
            mealDays: mealDays,
            // `hasSufficientData` takes the max across every body signal
            // rather than the union: one signal covering seven days is the
            // bar, not seven days of any-signal-at-all.
            bodyDays: max(healthDays, checkinDays)
        )
    }

    /// PostgREST returns `[{"<key>": "2026-09-10"}, …]`; nulls are possible on
    /// `eaten_date` for legacy rows and are not days.
    private static func distinctDays(
        _ data: Data, key: String, decoder: JSONDecoder
    ) throws -> Int {
        let rows = try decoder.decode([[String: String?]].self, from: data)
        var seen = Set<String>()
        for row in rows {
            if let value = row[key] ?? nil, !value.isEmpty { seen.insert(value) }
        }
        return seen.count
    }
}
