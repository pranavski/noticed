# Renamed to Somatic (2026-09-19)

Supersedes §5 of `docs/decisions/2026-09-10-positioning-and-pricing.md`, which
named the app **Noticed**. The app ships as **Somatic**. Everything else in
that record — positioning, pricing, the symptom-cohort framing — stands.

## What changed

Display name, App Store name (`Somatic: food and body`), purpose strings, all
user-visible copy, the hosted privacy policy and the listing copy.

## What deliberately did not change

| Identifier | Still says | Why |
|---|---|---|
| Bundle id | `com.pranavsurampudi.noticed` | It is the Sign in with Apple client id. Changing it means a new App ID, a new `.p8` key, four new secrets and a new Auth provider entry — all invisible to users. The `.soma` → `.noticed` move on 2026-09-19 cost exactly that. |
| Product id | `com.pranavsurampudi.noticed.yearly` | Permanent once created in App Store Connect; cannot be renamed at all. |
| Pages URLs | `pranavski.github.io/noticed/…` | Live and linked from the built app. A second move means another redirect stub and another App Store Connect edit. |
| Swift types, directories, storage keys | `Soma` | Unchanged since 2026-09-10, and now closer to the shipping name than before. |
| `Noticed.storekit` | filename only | Referenced by the shared scheme and by `SubscriptionStateTests`; its contents say Somatic. |

The rule: **the name is a product surface, not an identifier.** Every string a
reader sees says Somatic; every string Apple or Supabase keys off keeps its
original spelling.

## Open risk

"Somatic" is a common word in the wellness and therapy space. The trademark,
domain and App Store search checks that were run for *Noticed* do not carry
over, and none has been run for this name. `TODO.md` carries the item.
