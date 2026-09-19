# The paid line, and the gate that enforces it — 2026-09-19

Supersedes parts of `2026-09-10-positioning-and-pricing.md` §2 and §3.

That record decided *what* a subscription buys. This one decides what the
free tier actually costs to run, and how the server — not the phone — knows
who is entitled. It exists because the shipped code and the 2026-09-10
record disagreed, and because the ordering of the work has a failure mode
that destroys the product if it is done in the obvious sequence.

Status: decided. Execution state is tracked in `TODO.md`.

---

## 0. What was actually shipped, before any of this

Worth recording, because it is not what anyone would have guessed from
reading the decision record:

- The nightly fan-out enqueued **every consenting user with a recent meal**,
  subscriber or not. §3's "new insights stop" was never true.
- `MealLogger` invoked `parse-meal` for everyone. §3's "meals file as typed
  through the existing declined-consent path" was never wired up; the path
  exists and is tested, but nothing routed anyone to it.
- The only enforced gate was the client check on pull-to-refresh.

So the shipped line was **everything is free except pressing pull-to-refresh**
— a gate on the one action that costs the least. A free user who never
pulled received the whole product, generated nightly at our expense.

## 1. AI parsing is paid

A free account files meals as written, through `AIDisclosure.decline()` →
`parse_status = 'manual'`. Parsing is per-meal and is the dominant cost;
generation is not. Leaving parse free meant a lapsed user cost roughly
$0.75/month forever at zero revenue, and meant §4's margin arithmetic
quietly assumed every parsing user was a subscriber.

**The copy has to say so.** "Logging stays free" while silently downgrading
what logging produces is the kind of small lie this app does not tell — the
same standard `SubscriptionStore.isEligibleForTrial` already applies to the
trial claim. The paywall and the listing say: free accounts file meals as
you write them; a subscription reads them into ingredients.

**Not chosen:** free parsing with a monthly cap (the option §2 raised and
declined). It is still the most philosophically consistent answer — it gates
exactly the thing that costs money, in proportion — but it needs a counter,
a reset, a copy vocabulary for "7 of 30 left", and a decision about what
happens at zero. That is a feature, competing against a one-line routing
change that produces a defensible free tier today.

## 2. The nightly engine is gated too

The cron fan-out gains an entitlement join alongside the `ai_consent` join
it already carries. Without this, nothing else here matters: nobody
subscribes to unlock a button whose output arrives for free anyway.

**Not chosen:** leaving nightly generation open as a loss-leader, or
granting every free account one finding ever as a hook. The second collides
with §3's promise that existing insights stay visible and frozen — it would
manufacture a permanent one-insight account, and the one insight would be
whatever the statistics happened to find first, which may be nothing worth
reading. The trial is the hook.

## 3. Yearly only, at $15

No monthly SKU. A monthly option on a product whose value takes nine to
twelve days to first appear invites subscribe-then-cancel before the second
insight ever lands, and it doubles the entitlement states the server must
reason about in the same week that server is being written. Monthly can be
added later from strength; it cannot easily be withdrawn.

## 4. A trialist short of the gate is warned, not surprised

§2 sized the trial at 14 days because a realistic user clears the coverage
gate around calendar day 9–12. The tail is the problem: a sporadic logger
reaches day 14 having seen nothing, and is billed $15 for a feature they
have never once received.

`InsightCoverage` already computes, on-device, exactly how short they are.
So around day 11 of an active trial with the gate still uncleared, the
Noticed tab and the kitchen's "The nightly engine" row say it plainly —
how many days short, and how to cancel.

**In-app only.** Not a local notification: asking permission to send
notifications *in order to talk someone out of paying us* is a strange
prompt to add to an app that currently asks for two and is careful about
both. The honest limit: someone who has stopped opening the app will not
see this, and that is exactly the person who will not clear the gate. If
trial-to-charge complaints appear, revisit; do not build push speculatively.

---

## 5. How the server knows: the join, the writer, the reconciler

Do it the way `ai_consent` is done — a row the Edge Functions read before
spending a model call — with one inversion. `ai_consent` is written by the
client, because the client is the only thing that knows what the human
tapped. Entitlement is the opposite: a client-written entitlement row can be
forged with a single PostgREST call, and the RLS policy permitting the owner
to write it *is* the hole.

**The join is `appAccountToken`.** Set to the Supabase `user_id` UUID in the
purchase options; Apple echoes it in every App Store Server Notification and
on every transaction thereafter. Today it is set nowhere, which means Apple
currently has no way to say which of our users a transaction belongs to.

The healing path is a server-verified `originalTransactionID`: a transaction
restored on a device whose original purchase predates this code, or arriving
through Family Sharing, can carry no token. The client may report that id,
but the server verifies it against the App Store Server API before trusting
it — the client proposes, Apple confirms, the server writes.

**The writer of record is App Store Server Notifications V2**, verified by
its JWS signature chain. **The reconciler is the App Store Server API**,
called on demand when a user has no row but claims entitlement, and as a
periodic sweep. Apple retries failed notifications but does not guarantee
delivery, and an Edge Function has no uptime commitment; webhook-only means
one missed notification during a deploy locks out a paying subscriber with
no self-heal and no support staffing to rescue them.

**Not chosen:** polling the App Store Server API alone. It puts an Apple
round-trip in the path of the nightly fan-out for every user.

## 6. Fail closed — which is only safe because of the reconciler

No entitlement row, no generation. Not a grace window for new accounts: that
is a bypass anyone can farm with a fresh sign-in, which is the hole being
closed. Not open-for-user-path-closed-for-cron either — the user path is the
one an attacker controls.

**This decision is contingent.** Fail-closed without the reconciler of §5 is
a support burden with no escape hatch. If the reconciler is ever dropped,
this reopens.

## 7. Billing retry counts as entitled

Enable the 16-day App Store grace period and treat it as full entitlement. A
failed renewal is a bank's decision, not the reader's, and cutting someone
off mid-retry is the worst available moment to make this app feel punitive.
The marginal cost is a handful of Haiku calls. Grace recovers revenue that
otherwise churns on an expired card.

## 8. Shape of the row, and who may see it

One table, `user_id` primary key, owner-can-**select** and no write policy of
any kind. The service role bypasses RLS, so the webhook is unconstrained
while the client cannot forge. The select policy is not decoration: it lets
Settings show StoreKit's view and the server's view side by side, so a
disagreement — dropped webhook, reconciler not yet swept — reads as "your
device says subscribed, our server hasn't caught up" instead of an
inexplicable refusal, and can be debugged from a screenshot.

The row stores `environment` (Sandbox or Production) and **honours both**.
Every TestFlight purchase is Sandbox; honouring Production only would make
the device test matrix in `docs/deployment-checklist.md` §9 unrunnable.
Sandbox Apple IDs are minted inside our own App Store Connect account, not
by the public, so this is not a farmable bypass — but the column is stored
so the two can be told apart in logs.

## 9. `parse-meal` refuses by filing, not by erroring

A non-entitled call to `parse-meal` writes `parse_status = 'manual'` and
returns success. It does not return an error.

The client routes free users away from the call entirely, so this only fires
on a forged or stale request — but `MealLogger.invokeParse` turns any
failure into "couldn't read that one — try again?", which would be a lie:
the meal saved fine, it simply will not be parsed. Refusing *by filing*
makes the forged path and the legitimate path converge on the same correct
row, and leaves no error state to misreport.

## 10. One `.free` case, not two

`SubscriptionState` keeps three cases. Never-subscribed and lapsed are
identical *as entitlements*, which is what the type models; they differ only
in what the reader already has, which the database can answer. Copy branches
on whether any parsed meal exists. Splitting the case would double the
states every call site handles to encode something no call site needs.

---

## 11. The order of the work, and the landmine in it

Fail-closed enforcement shipped **before** the writer exists means an empty
table, universal refusal, and a dead product — including for us. The obvious
sequence is the fatal one.

So: table and `appAccountToken` first, then webhook and reconciler, then
enforcement. And enforcement arrives in **shadow mode**: the check computes
its verdict and logs what it *would* have refused, refusing nothing. It
flips to enforcing only after real notifications have been observed arriving
for real subscribers — a one-line change, revertible in a minute.

`appAccountToken` must be in the **first build capable of selling**.
Transactions made without it are unjoinable forever and no later deploy
repairs them. This is the only genuinely irreversible item on the list.

While shadow mode is running the app is not subscription-gated, and the App
Store Connect review notes must not say it is.

**Not chosen:** holding the first submission until all of it is enforced. It
puts an unbounded third-party integration in front of shipping. Also not
chosen: client-gate-only at 1.0 with the whole server half in 1.0.1 — that
throws away the only chance to validate the join against real purchases, and
risks shipping a sellable build with no `appAccountToken`.

---

## The honest limit on all of this

None of it is a fraud-proof gate, and it is not trying to be. A determined
person with a valid JWT and patience can still cost us model calls; what
changes is that the ordinary free user costs us nearly nothing, the paying
user gets what they paid for even when Apple's notification goes missing,
and the person who is about to be charged for something they have never seen
is told so first. The margin in §4 of the 2026-09-10 record gets better, not
worse — it no longer assumes that everyone whose meals we parse is paying.
