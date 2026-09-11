# Noticed — TODO

Live list. Everything the audit of 2026-09-07 called partially built or
broken has been fixed in code; what remains is hosting, App Store Connect
and deploy steps that need a human with credentials.

Positioning, pricing and the rename were decided 2026-09-10 —
`docs/decisions/2026-09-10-positioning-and-pricing.md`. The items that
decision created are listed under "From the 2026-09-10 decisions" below.

## From the 2026-09-10 decisions

- [x] `parse-meal` on `claude-sonnet-5`. **Needs a redeploy**
      (`supabase functions deploy parse-meal`) — the change is in the repo
      only.
- [x] Renamed to Noticed: display name, bundle ID
      (`com.pranavsurampudi.noticed`), purpose strings, all user-visible
      copy. Swift types, directories and storage keys deliberately unchanged.
- [x] Empty state counts down to the gate instead of "a couple more weeks",
      and distinguishes "not enough yet" from "looked, found nothing"
      (`InsightCoverage`, `InsightCoverageTests`).
- [x] App Store listing rewritten for the symptom cohort; new symptom-claim
      guardrail in `docs/app-store-compliance.md`.
- [ ] **BLOCKING — re-point Sign in with Apple at the new bundle id.**
      The native SIWA flow uses the bundle id AS the client id, so the
      rename broke it in three places at once: the Apple App ID, the
      Supabase Auth provider's Client ID, and the `APPLE_CLIENT_ID` secret
      (set 2026-09-08, still says `.soma`). Sign-in fails and deletion stops
      revoking until all three say `com.pranavsurampudi.noticed`. Full steps
      in `docs/deployment-checklist.md` §5. Fold this into the outstanding
      `.p8` key task below — the key must be created against the new App ID,
      so doing them separately means making the key twice. A simulator
      `SOMA_PREVIEW=1` run will NOT catch this.
- [ ] **Trademark and domain check on "Noticed"** — the App Store search
      check came back clean (1 near-match) but neither of these was run.
      Do this before anything is filed under the name.
- [ ] **Rename the GitHub repo and move the Pages URL.**
      `SomaFeatures.privacyPolicyURL` still points at
      `pranavski.github.io/soma/privacy/` **on purpose** — it is live and
      correct today, and repointing it before the repo moves would ship a
      404 as the privacy policy. Rename the repo, confirm the new Pages URL
      resolves, then change the constant and the App Store Connect field
      together.
- [x] **StoreKit subscription, client half.** `SubscriptionStore`,
      `SubscribeSheet`, the kitchen row, the pull-to-refresh gate and
      `Noticed.storekit` (wired into the shared scheme, so an Xcode run
      sells it locally). `SubscriptionStateTests` pins the product id, the
      P2W trial and the P1Y period against the config file.
- [x] **Free-tier gating.** Logging, record, export, reflections and
      already-surfaced findings are free forever and asserted as such in
      `SubscriptionStateTests`; only generation is gated.
- [ ] **App Store Connect: create the subscription product** —
      `com.pranavsurampudi.noticed.yearly`, $15/yr, 2-week free trial, and
      sign the Paid Applications agreement. Until then the paywall is empty
      in production. Steps in `docs/deployment-checklist.md` §9.
- [ ] **Server-side entitlement via App Store Server Notifications V2.**
      The client gate is UI only — the Edge Functions spend money and are
      reachable with any valid JWT. Must be a row the functions read, written
      by Apple's notifications, NOT by the client. Until it lands the
      subscription is not actually enforced; don't call the app
      subscription-gated in review notes. `docs/deployment-checklist.md` §9.3.

## Before the next TestFlight build

Done 2026-09-08: PR #3 merged to main; all 30 migrations applied; all four
Edge Functions deployed; GitHub Pages live; `privacyPolicyIsHosted` flipped.

- [ ] **Create the Sign in with Apple key and set the last two secrets.**
      `APPLE_CLIENT_ID` and `APPLE_TEAM_ID` (8VZH2497GC) are set;
      `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` are not, because the `.p8`
      only exists once a human makes it at developer.apple.com →
      Certificates → Keys → new key with "Sign in with Apple" enabled for
      the Soma App ID. Until then deletion works but Apple is never told —
      `delete-account` now logs exactly that, so check the function logs
      after the first test deletion.
- [ ] App Store Connect: privacy URL, support URL (both move with the repo
      rename above — do not file them until the new Pages URL resolves),
      nutrition label, age rating, review notes, screenshots — paste from
      docs/app-store-connect-copy.md; status in docs/app-store-compliance.md §6.
- [ ] Seed a reviewer-visible insight with docs/reviewer-seed.sql, record a
      short video, attach it to the submission.
- [ ] Re-shoot screenshots — the wordmark, the empty-state countdown and
      several copy strings all changed with the rename.
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
