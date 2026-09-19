# Soma — Deployment Checklist (v1.0 submission)

Everything below is what stands between the current repo and a live
TestFlight/App Store build. Run top to bottom.

> **State on 2026-09-08.** Done: every migration applied (30/30), all four
> functions deployed, GitHub Pages live at
> https://pranavski.github.io/soma/privacy/, `privacyPolicyIsHosted` true.
> Outstanding: `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` (§2) — the other two
> Apple secrets are set, so revocation is *half* configured and does
> nothing; `delete-account` logs which are missing. Then §6 (App Store
> Connect) and §8 (device smoke test).

## 1. Database

```sh
supabase migration list   # local and remote columns must match
supabase db push
```

Pushes whatever is unapplied. As of 2026-09-07 that is the three newest
migrations: `20260907120000_insights_read_only_for_clients.sql` (drops the
client write policies on `insights`), `20260907120100_create_insight_runs.sql`
(the per-user throttle table `generate-insights` reads) and
`20260907140000_create_ai_consent.sql` (the server-side consent row the
function and the cron fan-out check — without it no user gets nightly
insights, which is the safe direction). Verify:

```sh
supabase db diff        # should be empty
```

## 2. Edge Function secrets

```sh
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase secrets set INSIGHTS_CRON_SECRET=$(openssl rand -hex 32)

# SIWA token revocation (delete-account). All four required or the
# function silently skips revocation:
# Set 2026-09-08 — APPLE_CLIENT_ID IS NOW STALE, see the warning below:
#   supabase secrets set APPLE_CLIENT_ID=com.pranavsurampudi.noticed
#   supabase secrets set APPLE_TEAM_ID=8VZH2497GC
# Still needed — the .p8 does not exist until you create it:
supabase secrets set APPLE_KEY_ID=<key id of the .p8 SIWA key>
supabase secrets set APPLE_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)"
```

The `.p8` key comes from developer.apple.com → Certificates → Keys →
create a key with "Sign in with Apple" enabled, configured for the Soma
App ID.

## 3. Deploy functions

```sh
supabase functions deploy parse-meal
supabase functions deploy submit-correction
supabase functions deploy delete-account
supabase functions deploy generate-insights --no-verify-jwt
```

`generate-insights` must skip JWT verification (it authenticates with the
cron bearer secret, not a user JWT) — `config.toml` already carries
`[functions.generate-insights] verify_jwt = false`, and the flag makes it
explicit on deploy.

## 4. Vault secrets for the nightly cron

In the SQL editor (values must match step 2/3):

```sql
select vault.create_secret(
  'https://<project-ref>.supabase.co/functions/v1',
  'edge_function_base_url'
);
select vault.create_secret(
  '<same value as INSIGHTS_CRON_SECRET>',
  'insights_cron_secret'
);
```

Then confirm the job exists: `select * from cron.job;` — expect the nightly
03:30 UTC `generate-insights` fan-out (one POST per user with a meal in the
last 30 days; migration `20260720120200`).

## 5. Supabase Auth — Apple provider

> **BLOCKING after the 2026-09-10 rename.** The bundle id moved from
> `com.pranavsurampudi.soma` to `com.pranavsurampudi.noticed`, and for the
> native Sign in with Apple flow **the bundle id is the client id**. Until
> all three of the following agree, sign-in fails outright and account
> deletion silently stops revoking Apple tokens:
>
> 1. **Apple Developer portal** — an App ID for `com.pranavsurampudi.noticed`
>    with Sign in with Apple enabled. The existing `.soma` App ID cannot be
>    renamed; create the new one, and create the SIWA key against it (this
>    is the same `.p8` step still outstanding in TODO.md, so do both at once
>    rather than making a key twice).
> 2. **Supabase Auth provider** — Client ID below.
> 3. **`APPLE_CLIENT_ID` secret** — re-set for `delete-account`; the value
>    set on 2026-09-08 still says `.soma`.
>
> Do this before any TestFlight build goes to a device. A simulator run
> with `SOMA_PREVIEW=1` skips sign-in entirely and will not catch it.

Dashboard → Authentication → Providers → Apple:
- Client ID: `com.pranavsurampudi.noticed` (the app bundle id — native flow).
- No secret needed for the native `signInWithIdToken` flow.

## 6. App Store Connect

- **Privacy policy URL** — host `docs/privacy-policy.md` (GitHub Pages is
  the plan), set the URL in ASC, then point `SomaFeatures.privacyPolicyURL`
  at it and flip `SomaFeatures.privacyPolicyIsHosted`. Required before
  submission.
- **Support URL / email** — `SomaFeatures.supportEmail`.
- **App privacy nutrition labels** — declare exactly what
  `PrivacyInfo.xcprivacy` declares: Health & Fitness, Other User Content,
  User ID, Email, Other Diagnostic Data — all "linked to you", none
  "tracking". See docs/app-store-compliance.md §2.
- **App icon** — present; `DesignAssets/build-assets.sh` regenerates it
  from the master PNG.
- Screenshots: iPhone only (the target is iPhone-only, portrait-only).
  Do not show or mention photo logging — it is not in this version.
- **Copy and review notes** — drafted in `docs/app-store-connect-copy.md`;
  paste from there.
- **Reviewer can't see an insight** — the engine needs ~10 paired days.
  Run `docs/reviewer-seed.sql` against your own account before the
  screenshots and the review video (see that file's header).

## 7. Xcode / signing sanity

- `MARKETING_VERSION = 1.0`, `TARGETED_DEVICE_FAMILY = 1`, portrait-only —
  already set in the project.
- Capabilities on the App ID: Sign in with Apple + HealthKit.
- Build with a real distribution certificate; HealthKit + SIWA need the
  entitlements present in the profile.

## 8. Post-deploy smoke test

1. Fresh install → Sign in with Apple → log a meal by voice and by typing.
2. Check `meals` row has `eaten_date`/`eaten_hour` populated in local time.
3. Connect HealthKit in Settings → confirm `health_days` rows appear and
   that re-foregrounding the app within 6h does **not** re-sync.
4. Settings → export CSV → share sheet opens with data.
5. Settings → delete account → complete the Apple prompt → confirm all
   rows gone and sign-in state cleared; then cancel-path: delete again on
   a second account, dismiss the Apple prompt, deletion must still finish.
6. Pull to refresh on the Noticed tab twice in a row: the second pull
   should show "thought it over a few minutes ago" (the 429 throttle),
   not a failure.
7. Consent, server-side: on an account that tapped "not now", confirm
   `select * from ai_consent where user_id = '<uuid>'` shows
   `consented = false`, then run step 8's curl for that user — expect
   `{"surfaced":false,"reason":"no_ai_consent",...}` and no row in
   `insight_runs` with a model call behind it. Flip consent on in the
   kitchen → Reading meals and re-run: the reason changes.
8. Invoke `generate-insights` manually with the cron secret and confirm the
   insufficient-data / insight / empty-state responses behave per spec:
   ```sh
   curl -X POST https://<ref>.supabase.co/functions/v1/generate-insights \
     -H "Authorization: Bearer $INSIGHTS_CRON_SECRET" \
     -H "Content-Type: application/json" -d '{"user_id":"<uuid>"}'
   ```

## 9. Subscription (StoreKit)

The client half is built: `SubscriptionStore` (entitlement), `SubscribeSheet`
(paywall), the "The nightly engine" row in the kitchen, and the gate on
pull-to-refresh. `Noticed.storekit` is referenced by the shared scheme, so a
**Xcode** run sells the product locally — a `simctl launch` does not read the
scheme, so the paywall there shows "—" and a disabled button, which is the
intended offline fallback rather than a bug.

What is not built, in the order it has to happen:

1. **App Store Connect** — create the auto-renewable subscription. Product ID
   `com.pranavsurampudi.noticed.yearly`, one subscription group, $15/year,
   with a **2-week free-trial introductory offer**. These three values are
   asserted by `SubscriptionStateTests.testProductIDMatchesTheStoreKitConfiguration`
   against `Noticed.storekit`; ASC has to agree with both or the paywall is
   empty in production with no error.

   The trial is 14 days and not 7 on purpose: the insight gate needs seven
   days *on which a meal was logged*, which a realistic user reaches around
   calendar day 9–12. A 7-day trial bills people the day before their first
   finding. See `docs/decisions/2026-09-10-positioning-and-pricing.md` §2.

2. **Paid Applications agreement + banking.** Products stay in "Missing
   Metadata"/"Waiting for Review" and never load until this is signed.

3. **Server-side entitlement — the gate that actually matters.**
   `SubscriptionStore` decides what the *app* offers. It does not and cannot
   decide what the *server* does: `parse-meal` and `generate-insights` cost
   real money per call and are reachable by anyone holding a valid JWT, so a
   client-only check is a UI affordance, not a gate.

   The design is decided in full — read
   `docs/decisions/2026-09-19-subscription-enforcement.md` §5–§11 before
   starting. In the order it has to be done, because the obvious order
   bricks the app:

   1. **`appAccountToken` in the first sellable build.** Set it to the
      Supabase `user_id` in the purchase options in `SubscriptionStore`.
      Apple echoes it in every notification; transactions bought without it
      can never be joined to a user, and no later deploy repairs them. This
      is the only irreversible item here.
   2. **The entitlement table.** Shaped like `ai_consent` with one
      inversion — the client gets an owner-can-**select** policy and no
      write policy of any kind. The service role bypasses RLS, so the
      webhook writes freely while the client cannot forge. Store
      `environment` and honour both Sandbox and Production (every TestFlight
      purchase is Sandbox; step 4 below is unrunnable otherwise).
   3. **The ASSN V2 webhook** — an Edge Function that verifies the JWS
      signature chain and upserts. Configure both the production and sandbox
      notification URLs in App Store Connect. **Enable the 16-day grace
      period** and treat billing retry as entitled.
   4. **The reconciler** — an App Store Server API lookup, run on demand
      when a user claims entitlement with no row, and as a periodic sweep.
      Fail-closed enforcement is only safe because this exists; if it is
      dropped, the fail-closed decision reopens.
   5. **The checks, in shadow mode first.** The entitlement join on the cron
      fan-out, the re-check inside `generate-insights`, and `parse-meal`'s
      refusal (which writes `parse_status = 'manual'` and returns success —
      never an error; see §9 of the decision record). Each logs the verdict
      it *would* have enforced. Flip to enforcing only after real
      notifications have been seen arriving for real subscribers.

   Until step 5 is flipped the subscription is not enforced: the nightly
   cron fans out to every consenting user regardless. That is *safe* (it
   costs money, it leaks nothing) — but do not describe the app as
   subscription-gated in App Store Connect review notes before the flip.

4. **Device test matrix**: buy with a sandbox Apple ID; confirm the trial
   shows "14 days free first" on a fresh sandbox account and does *not* on
   one that has already used it; cancel in sandbox and confirm the app falls
   back to the free tier with meals, export, reflections and existing
   findings all intact; restore on a second device. Also confirm the free
   tier files a meal as typed (`parse_status = 'manual'`) rather than
   erroring, and that the Settings row shows the device's view and the
   server's view of entitlement side by side.
