# Noticed — TODO

Live list. Everything the audit of 2026-09-07 called partially built or
broken has been fixed in code; what remains is hosting, App Store Connect
and deploy steps that need a human with credentials.

Positioning, pricing and the rename were decided 2026-09-10 —
`docs/decisions/2026-09-10-positioning-and-pricing.md`. The items that
decision created are listed under "From the 2026-09-10 decisions" below.

## From the 2026-09-10 decisions

- [x] `parse-meal` on `claude-sonnet-5` — deployed 2026-09-19 (v10).
- [x] Renamed to Noticed: display name, bundle ID
      (`com.pranavsurampudi.noticed`), purpose strings, all user-visible
      copy. Swift types, directories and storage keys deliberately unchanged.
- [x] Empty state counts down to the gate instead of "a couple more weeks",
      and distinguishes "not enough yet" from "looked, found nothing"
      (`InsightCoverage`, `InsightCoverageTests`).
- [x] App Store listing rewritten for the symptom cohort; new symptom-claim
      guardrail in `docs/app-store-compliance.md`.
- [x] **BLOCKING — re-point Sign in with Apple at the new bundle id.**
      **Done 2026-09-19** — the Auth provider's Client ID is now
      `com.pranavsurampudi.noticed,com.pranavsurampudi.soma` (drop `.soma`
      once no old builds are installed). Remaining: verify sign-in on a
      real device.
      The native SIWA flow uses the bundle id AS the client id, so the
      rename broke it in three places at once: the Apple App ID, the
      Supabase Auth provider's Client ID, and the `APPLE_CLIENT_ID` secret.
      Sign-in fails and deletion stops
      revoking until all three say `com.pranavsurampudi.noticed`. Full steps
      in `docs/deployment-checklist.md` §5. Fold this into the outstanding
      `.p8` key task below — the key must be created against the new App ID,
      so doing them separately means making the key twice. A simulator
      `SOMA_PREVIEW=1` run will NOT catch this.
- [ ] **Trademark and domain check on "Noticed"** — the App Store search
      check came back clean (1 near-match) but neither of these was run.
      Do this before anything is filed under the name.
- [x] **Rename the GitHub repo and move the Pages URL.** Done 2026-09-19:
      repo is `pranavski/noticed`; https://pranavski.github.io/noticed/privacy/
      verified 200 before `SomaFeatures.privacyPolicyURL` moved to it. The
      old `/soma/` and `/soma/privacy/` paths redirect via stubs in the
      `pranavski.github.io` repo (`soma/`), so earlier builds keep a working
      link — delete the stubs only if a repo named `soma` is ever recreated.
      App Store Connect was never filed with the old URL; use the new one
      (see `docs/app-store-connect-copy.md`).
- [x] **StoreKit subscription, client half.** `SubscriptionStore`,
      `SubscribeSheet`, the kitchen row, the pull-to-refresh gate and
      `Noticed.storekit` (wired into the shared scheme, so an Xcode run
      sells it locally). `SubscriptionStateTests` pins the product id, the
      P2W trial and the P1Y period against the config file.
- [x] **Free-tier gating.** Logging, record, export, reflections and
      already-surfaced findings are free forever and asserted as such in
      `SubscriptionStateTests`. **Amended 2026-09-19:** AI parsing is no
      longer free — see the next section.
- [ ] **App Store Connect: create the subscription product** —
      `com.pranavsurampudi.noticed.yearly`, $15/yr, 2-week free trial, and
      sign the Paid Applications agreement. Until then the paywall is empty
      in production. Steps in `docs/deployment-checklist.md` §9.
      **2026-09-19:** group "Noticed" and the product exist (1 year, display
      name "Noticed, yearly", description trimmed to ASC's 55-char limit:
      "The nightly engine. Your notebook stays free."), upfront billing in
      all 175 countries. **Blocked:** saving a price errors until the
      Account Holder accepts the updated Developer Program License Agreement
      and signs the Paid Apps agreement (only Free Apps is active). After
      that: price $15.00, then the 2-week free introductory offer, then a
      paywall screenshot for review.

## From the 2026-09-19 subscription-enforcement decisions

Design decided in full in
`docs/decisions/2026-09-19-subscription-enforcement.md`; execution order and
the landmine in it are in `docs/deployment-checklist.md` §9.3. Do them in
this order — fail-closed checks shipped before the writer exists mean an
empty table, universal refusal, and a dead app.

- [x] Decision record, `CONTEXT.md` glossary, checklist §9.3 rewritten,
      supersession notes on the 2026-09-10 record §2–§3.
- [x] **`appAccountToken` = the Supabase `user_id`** in
      `SubscriptionStore.purchase()`. One line, and the only irreversible
      item on this list: transactions bought without it can never be joined
      to a user. Must be in the first build capable of selling.
- [x] **AI parsing moves to the paid side.** `MealLogger` routes a
      non-entitled reader down the existing `AIDisclosure.decline()` /
      `parse_status = 'manual'` path instead of calling `parse-meal`. Add
      `canParseMeals` to `SubscriptionState` and assert it in
      `SubscriptionStateTests` alongside the five free-forever promises.
- [x] **Paywall and listing copy** say what is actually paid: free accounts
      file meals as written, a subscription reads them into ingredients.
      `SubscribeSheet`, `docs/app-store-connect-copy.md`.
- [x] **Trial-tail warning.** `TrialTailWarning` + `TrialTailWarningTests`;
      the Noticed tab carries the shortfall and the cancel path, the kitchen
      row carries the countdown only (coverage is three network reads).
      In-app only — no notification permission prompt.
- [ ] **Entitlement table** (`ai_consent`-shaped, owner-can-select, no write
      policy, stores `environment`, honours Sandbox and Production).
- [ ] **ASSN V2 webhook** Edge Function: verify the JWS chain, upsert.
      Configure both notification URLs in ASC; enable the 16-day grace
      period and treat billing retry as entitled.
- [ ] **Reconciler** against the App Store Server API — on demand when a
      user claims entitlement with no row, plus a periodic sweep. The
      fail-closed decision depends on this existing.
- [ ] **The checks, shadow mode first**: entitlement join on the cron
      fan-out, re-check inside `generate-insights`, `parse-meal` refusing by
      filing `manual` rather than erroring. Log the verdict, enforce
      nothing, flip only after real notifications are seen arriving.
- [ ] Settings row showing the device's view and the server's view of
      entitlement side by side (this is what the select policy is for).
- [x] **Guideline 3.1.2 paywall disclosures.** `SubscribeSheet` now says
      the subscription renews itself each year until cancelled (and that the
      14 free days become the first paid year), and carries both required
      links: terms of use → `SomaFeatures.termsOfUseURL`, Apple's standard
      EULA; privacy → the in-app policy sheet, which needs no network.
      `docs/app-store-compliance.md` has a 3.1.2 section now, and
      `SubscriptionStateTests.testPaywallCarriesTermsAndPrivacyLinks` pins
      the links so a typo fails a test rather than a review.
      **One ASC condition:** leave the App Store Connect "License Agreement"
      field at Apple's standard EULA, or file a custom one and move the
      constant with it in the same change.

## Before the next TestFlight build

Done 2026-09-08: PR #3 merged to main; all 30 migrations applied; all four
Edge Functions deployed; GitHub Pages live; `privacyPolicyIsHosted` flipped.

- [x] **Create the Sign in with Apple key and set the last two secrets.**
      Done 2026-09-19: key `LRCDV553QF` created against the `.noticed` App
      ID; `APPLE_CLIENT_ID` (now `com.pranavsurampudi.noticed`),
      `APPLE_TEAM_ID` (8VZH2497GC), `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY`
      all set and hash-verified. Still check the `delete-account` logs after
      the first test deletion to confirm Apple is actually told.
- [ ] App Store Connect: the app record for `com.pranavsurampudi.noticed`
      exists (created 2026-09-19). Still to fill: privacy URL, support URL
      (the `/noticed/` URLs are live — file those, not `/soma/`),
      nutrition label, age rating, review notes, screenshots — paste from
      docs/app-store-connect-copy.md; status in docs/app-store-compliance.md §6.
- [ ] Seed a reviewer-visible insight with docs/reviewer-seed.sql, record a
      short video, attach it to the submission.
- [x] Re-shoot screenshots — done 2026-09-19, six captioned 6.9" frames in
      `DesignAssets/screenshots/iphone-6.9/` (`capture.sh` + `compose.py`
      regenerate them). Upload them in ASC with the item above.
- [ ] Device smoke test, docs/deployment-checklist.md §8 — especially
      deletion (step 5) and the consent-decline path (step 7).

## Nice to have, not blocking
- [ ] `scripts/build-fdc-reference.ts` has never been run to completion;
      `_shared/fdc-reference.json` is empty and the composition block in
      the parse prompt is dormant until it is.
- [ ] Macro / caffeine / alcohol ranges are not editable from the
      correction sheet; after a correction the meal keeps Claude's values
      for those six.
- [ ] Feedback rows (`app_feedback`) have no inbox beyond the SQL console.
- [ ] Meal plans — design note only (docs/meal-plans-design.md), no code.

## Done (kept for the record)
- AI consent enforced server-side (`ai_consent`), not just on the phone.
- Voice / typed meal → pending row → Claude parse → Today card.
- Declined AI consent files the meal as written, correction open.
- Corrections rewrite meal_items; corrected rows repeatable and re-correctable.
- HealthKit read-only rollup, background delivery, disconnect, purpose
  string names all seven types.
- Nightly + on-demand insight engine with FDR, evidence layer, reflections,
  per-user throttle on pull-to-refresh.
- Fonts bundled (Caveat, Fraunces, IBM Plex Mono).
- Wax-paper "compare yesterday" on Today.
- CI (Deno tests + iOS build/tests), README.
