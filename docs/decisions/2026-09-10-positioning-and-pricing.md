# Positioning, pricing and the rename — 2026-09-10

What was decided in one sitting, and why. Recorded because the reasoning is
not recoverable from the diffs: several of these decisions look arbitrary
without the arithmetic behind them, and at least two reverse a previous
choice made for good reasons that no longer hold.

Status: decided. Execution state is tracked in `TODO.md`.

---

## 1. The audience is the symptom cohort, not "people who cook"

Previous framing (README, App Store description) aimed at people who cook and
want to notice how food and the body move together. That is a taste-shaped
audience, not a pain-shaped one, and people who cook are not in pain about
cooking.

Repointed at people who suspect something they eat is affecting how they
feel — sleep, stomach, energy — and who have been told confidently wrong
things by an app before.

**Why it follows from what was already built.** The hedging, the FDR
correction, the refusal to promise an outcome, the `pattern_history` audit
trail: all of it is worthless as a selling point to someone browsing for a
food diary, and is the entire pitch to someone who has been misled. This
audience also tolerates the seven-day wait, because they have already spent
years not knowing.

Secondary channel is the quantified-self / HN audience, as a megaphone rather
than a market. The statistics writeup — the FDR correction, the 21/300
noise-window measurement, why rejected associations are stored — is the thing
that travels there.

**Not chosen:** the general wellness audience ("is coffee wrecking my
sleep"). Biggest, vaguest, most expensive to reach, and contested by
far better-funded competitors.

## 2. Subscription at $15/yr through StoreKit, 14-day trial

> **Amended 2026-09-19.** The capped-free-tier option declined below was
> reopened and declined again for a different reason, and the trial's tail
> case — a sporadic logger billed before ever clearing the coverage gate —
> is now warned in-app rather than accepted. Yearly-only is reaffirmed.
> See `2026-09-19-subscription-enforcement.md` §1, §3, §4.

- **StoreKit IAP, not Stripe.** Guideline 3.1.1 requires IAP to unlock
  functionality. The US link-out carve-out following the 2025 Epic injunction
  would permit Stripe on the US storefront only, and Stripe's own rate on a
  small transaction is worse than Apple's 15% under the Small Business
  Program. One payment path, not two.
- **$15/yr**, chosen to stay affordable rather than to maximise revenue.
- **14-day trial, not 7.** The gate is seven days *on which a meal was
  logged*. Nobody logs seven of seven, so a realistic user reaches the
  threshold somewhere around calendar day 9–12. A 7-day trial therefore bills
  people the day before their first insight, for a feature they have never
  seen. 14 days clears the realistic window.
- **Trial cost is not a concern.** `generate-insights` returns
  `insufficient_data` before any model call, so a trialist costs nothing on
  the insight side until they clear the gate. Roughly $0.35 per trialist.

**Not chosen:** a free tier with capped AI parses and no subscription. It
fits the philosophy better (it gates only the thing that costs money) but was
judged to complicate the first release.

## 3. What a lapsed subscriber keeps

> **Superseded in part, 2026-09-19.** What this section describes was never
> built: the nightly fan-out ran for every consenting user and `parse-meal`
> was called for everyone, so in the shipped app only pull-to-refresh was
> gated. The line below is now the intended one *and* the enforced one, with
> AI parsing explicitly on the paid side of it. See
> `2026-09-19-subscription-enforcement.md` §0–§2 and §5–§11.

Logging stays free forever. Meals file as typed through the existing
declined-consent path (`AIDisclosure.decline()`, `parse_status = 'manual'`),
which is already built and tested. Existing insights stay visible, frozen.
New insights stop.

**Reflections stay live and free.** `reflections.ts` is pure TypeScript
templating with no model call by explicit design, so a free account can keep
receiving accurate daily descriptions of its own log at zero marginal cost.

The line this draws: **descriptions are free, inferences are paid.** It is
also the best advertisement available, since a free user watches reflections
accumulate and can see what sits behind them.

**Not chosen:** locking the record behind the paywall. It would contradict
the export-everything and delete-everything commitments the app already
makes.

## 4. Cost: one model swap, and two levers that turned out to be built

`parse-meal` moved from `claude-sonnet-4-6` ($3/$15 per MTok) to
`claude-sonnet-5` ($2/$10) — newer generation and cheaper on both sides. The
request sends no `temperature` / `top_p` / `budget_tokens`, so the swap
needed no other change.

Two further savings were proposed and then found already in the code:

- **Prompt caching** is on the system block (`cache_control`, ~1,630 tokens,
  above Sonnet 5's 1024-token minimum). It is worth understanding that this
  **does not save anything yet**: the entry has a 5-minute TTL, so below
  roughly one parse every five minutes across the entire user base every call
  is a cold write at 1.25× and costs ~25% *more* than not caching. It flips
  to a large win above that rate with no deploy. See the comment at the call
  site.
- **The nightly short-circuit** already exists: `generate-insights` returns
  `no_qualifying_patterns` before `callClaude` when nothing new survived the
  correction. The nightly Haiku call therefore fires only on nights that
  produced a genuinely new pattern, not 30 times a month.

**Revised steady-state cost: ~$0.75/user/month**, against ~$1.06 net at
$15/yr after Apple's 15%. Roughly 29% gross margin, positive for a normal
user and near break-even for a heavy one.

## 5. Renamed to Noticed

"Soma" collides with a muscle relaxant, *Brave New World*, a San Francisco
district and other apps, and wins no search.

Candidates were checked against the App Store search API for apps whose name
matches or begins with the term:

| candidate | matching apps | note |
|---|---|---|
| **Noticed** | **1** | "NOTICED YOU" — not a collision |
| Mise | 11 | every one a food app; the design system's own direction word is the worst available option |
| Larder | 11 | meal planners |
| Vellum | 22 | includes the well-known writing tool |
| Trace / Margin | 26 / 20 | crowded |
| Quill / Kept / Tally | 35 / 43 / 62 | saturated |

Shipping as `Noticed — food & body journal`: Apple weights the name field in
search, so the tail does keyword work while the word carries the brand.

**Scope of the rename.** Display name, bundle ID
(`com.pranavsurampudi.noticed`), permission purpose strings, and every
user-visible string. Deliberately *not* renamed: Swift types (`SomaFeatures`,
`Font.Soma`), directory names, the repo layout, and storage keys
(`com.soma.supabase.auth`, `soma.healthkit.*`, `soma.ai.parseConsent.v1`) —
changing a storage key signs every existing account out for no user benefit.
The bundle ID was changed **now** because it is immutable after first
submission.

**Two consequences worth knowing.** First, the name is a common past-tense
verb, so lowercase house style breaks down: *"noticed reads your meal"* parses
as a verb, not a name. The name is therefore capitalised in body copy even
though the rest of the voice is lowercase — the standard exception for proper
nouns. Second, one sentence had to be reworded rather than renamed, because
"what Noticed notices" is unreadable (`MealCardActions.swift`).

Trademark and domain are **not yet checked**.

## 6. The empty state now counts down

`MIN_MEAL_DAYS` / `MIN_BODY_DAYS` are mirrored client-side in
`InsightCoverage`, pinned by `InsightCoverageTests` so they cannot drift from
`digest.ts` silently. The Noticed tab names the shortfall and what is already
covered, instead of "a couple more weeks" forever.

It also distinguishes two states the old copy conflated: **before** the gate
("2 more days with a meal logged"), and **past** it, where an empty feed means
the statistics found nothing — a result, not a wait. The footer stops saying
"keep logging" at that point and says "a quiet month is a real result."

## 7. Photo logging stays deferred

The schema, the bucket and `parse-meal`'s photo path stay dormant. This
audience eats repetitively — restricted diets, the same safe meals — which is
the case where voice plus one-tap repeat beats photography. Image input
tokens would also undo the margin decided in §4. Photo is table stakes for
calorie counters aimed at people eating out; it is close to irrelevant here.

---

## The honest limit on all of this

None of these decisions makes this a business. At ~29% gross margin, a
thousand paying subscribers is roughly $3k/year. What they change is that the
app stops losing money on every user while staying honest about what it
knows. The plausible upside is that the *engine* gets noticed — by the
quantified-self community, a clinician-facing tool, or anyone who eventually
wants a correlation layer that does not lie.
