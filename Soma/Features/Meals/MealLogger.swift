import Foundation
import Supabase

/// The one path a meal takes onto the record: insert the row, then hand it
/// to `parse-meal`.
///
/// Today logs against now and History logs against a day you pick, but the
/// steps in between are identical — the row has to exist before the parse
/// so a "parsing…" card can render, the Claude call is gated on consent and
/// on entitlement, and a parse failure is a soft note rather than a lost
/// meal. That sequence lived inside `TodayViewModel`; it lives here so
/// backdating a meal from History can't quietly drift from logging one on
/// Today.
///
/// **Two different reasons file a meal as written**, and they must read
/// differently to the person holding the phone: consent declined is a choice
/// they made and can unmake in the kitchen, entitlement is a thing they can
/// buy. Neither ever blocks the meal.
@MainActor
struct MealLogger {
    /// What the caller has to know afterwards. `note` is soft — the meal is
    /// saved either way — and `parseAttempted` says whether a second read of
    /// the row is worth it, since only a parse can have changed it.
    struct Receipt {
        let mealId: UUID
        let note: String?
        let parseAttempted: Bool
    }

    private let repository: MealsRepository
    private let client: SupabaseClient
    private let disclosure: AIDisclosure

    init(
        repository: MealsRepository = MealsRepository(),
        client: SupabaseClient = .shared,
        // Resolved in the body rather than as a default argument, which is
        // evaluated at the (non-isolated) call site — AIDisclosure is
        // @MainActor.
        disclosure: AIDisclosure? = nil
    ) {
        self.repository = repository
        self.client = client
        self.disclosure = disclosure ?? .shared
    }

    /// Spoken or typed meal. `onInserted` runs once the row exists and
    /// before the parse round-trip, so the screen can put a "parsing…" card
    /// up instead of holding a spinner over the whole flow.
    ///
    /// `canParseMeals` is the entitlement, passed in rather than read here —
    /// the same shape `InsightsViewModel.refresh(canGenerate:)` uses, and for
    /// the same reason: this type stays testable without StoreKit. It has no
    /// default on purpose. A call site that forgets it should fail to compile
    /// rather than quietly ship free parsing.
    func log(
        transcript: String,
        source: Meal.Source,
        eatenAt: Date,
        canParseMeals: Bool,
        onInserted: () async -> Void
    ) async throws -> Receipt {
        // Guideline 5.1.2(i): no personal data reaches Anthropic without
        // explicit consent. With consent off the meal is filed as written —
        // a `manual` row titled with the person's own words, no spinner, and
        // "not quite right?" open from the start to fill in the rest.
        guard disclosure.hasConsented else {
            return try await fileAsWritten(
                transcript: transcript,
                source: source,
                eatenAt: eatenAt,
                note: "filed as written — Noticed won't send it to Claude until you say it's ok, see the kitchen. press and hold the card to fill in the details.",
                onInserted: onInserted
            )
        }

        // Reading a meal into ingredients is the paid half of the line drawn
        // in `docs/decisions/2026-09-19-subscription-enforcement.md` §1. A
        // free account still logs everything, in its own words, down the same
        // path a declined-consent account takes — so nothing is lost, only
        // left unread. The correction sheet fills in the rest by hand.
        guard canParseMeals else {
            return try await fileAsWritten(
                transcript: transcript,
                source: source,
                eatenAt: eatenAt,
                note: "filed in your words — reading meals into ingredients comes with the nightly engine, see the kitchen. press and hold the card to fill in the details.",
                onInserted: onInserted
            )
        }

        let mealId = try await repository.insertPendingMeal(
            source: source,
            voiceTranscript: transcript,
            eatenAt: eatenAt
        )

        await onInserted()

        struct ParseRequest: Encodable {
            let meal_id: UUID
            let voice_transcript: String
        }

        return await invokeParse(
            mealId: mealId,
            body: ParseRequest(meal_id: mealId, voice_transcript: transcript)
        )
    }

    /// A meal that will not be read: the row is the person's own words, the
    /// correction sheet is open from the start, and no spinner is shown. A
    /// `pending` row here would spin forever, because nothing is coming to
    /// finish it.
    private func fileAsWritten(
        transcript: String,
        source: Meal.Source,
        eatenAt: Date,
        note: String,
        onInserted: () async -> Void
    ) async throws -> Receipt {
        let mealId = try await repository.insertWrittenMeal(
            transcript: transcript,
            source: source,
            eatenAt: eatenAt
        )
        await onInserted()
        return Receipt(mealId: mealId, note: note, parseAttempted: false)
    }

    /// One-tap repeat of a prior dish, on whichever day the caller names.
    /// No Edge Function round-trip — the parse came with the original.
    @discardableResult
    func repeatDish(_ dish: String, eatenAt: Date) async throws -> UUID {
        try await repository.repeatMeal(dishName: dish, eatenAt: eatenAt)
    }

    /// A 422 from the function is the documented Claude-failure path — it
    /// still updates the row to parse_status='failed', so the caller reloads
    /// and shows a soft note rather than a hard error.
    private func invokeParse(mealId: UUID, body: some Encodable) async -> Receipt {
        do {
            try await client.functions.invoke(
                "parse-meal",
                options: FunctionInvokeOptions(body: body)
            )
            return Receipt(mealId: mealId, note: nil, parseAttempted: true)
        } catch {
            return Receipt(
                mealId: mealId,
                note: "couldn't read that one — try again?",
                parseAttempted: true
            )
        }
    }
}
