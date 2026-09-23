import StoreKit
import SwiftUI

/// The paywall.
///
/// It leads with what stays free, which is unusual and deliberate. This app
/// is aimed at people who have been told confidently wrong things by health
/// apps before; a paywall that hides the free tier would be the first small
/// dishonesty, and it would be the one they are primed to notice.
///
/// No urgency, no countdown, no "most popular" badge, no crossed-out price.
/// One price, one button, and an honest sentence about what happens if you
/// never pay: everything you have written down stays yours and keeps working.
///
/// Since 2026-09-19 a subscription buys two things, not one — reading a meal
/// into ingredients, and the nightly look at what that adds up to. The first
/// is named here plainly rather than left for someone to discover when their
/// first free meal files as a bare line of their own words. See
/// `docs/decisions/2026-09-19-subscription-enforcement.md` §1.
struct SubscribeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @State private var isWorking = false
    @State private var trialAvailable = false
    @State private var showingPrivacy = false

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header

                    Text("it keeps looking,\nevery night.")
                        .font(Font.Soma.pullQuote)
                        .foregroundStyle(Color.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("it reads what you log — \"eggs on sourdough\" becomes "
                       + "ingredients and a range — and then, every night, it "
                       + "scores all of it against how your days went, corrects "
                       + "for having looked at a lot of pairings at once, and "
                       + "writes up only what survives. most nights that's "
                       + "nothing, and it says so.")
                        .font(Font.Soma.dishNote)
                        .foregroundStyle(Color.inkSoft)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    InkRule(style: .dotted, color: Color.rule, weight: Theme.Stroke.hairline)
                        .frame(height: 4)

                    staysFree

                    priceRow

                    if let error = subscriptions.purchaseError {
                        Text(error)
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.persimmon)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    actionRow

                    renewalTerms

                    Text("if you stop, nothing is taken away — your meals, your "
                       + "record, your export and the daily notes about your own "
                       + "log all keep working, and the findings you've already "
                       + "been shown stay where they are. new meals file in your "
                       + "own words from then on, and you can fill in the details "
                       + "by hand whenever you like.")
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    legalLinks

                    Spacer(minLength: 40)
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .task {
            trialAvailable = await subscriptions.isEligibleForTrial
        }
        .sheet(isPresented: $showingPrivacy) {
            PrivacyPolicySheet()
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            Text("THE NIGHTLY ENGINE")
                .font(Font.Soma.sectionTag)
                .tracking(2)
                .foregroundStyle(Color.inkSoft)
            Spacer()
            Button { dismiss() } label: {
                Text("not now")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.inkSoft)
            }
            .buttonStyle(.plain)
        }
    }

    /// Named explicitly, above the price, because it is the more surprising
    /// half and the half a reader assumes is a trick.
    private var staysFree: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("FREE, ALWAYS")
                .font(Font.Soma.sectionTag)
                .tracking(2)
                .foregroundStyle(Color.inkSoft)

            ForEach([
                "logging meals — by voice, by hand, or one tap to repeat — "
                    + "filed in your own words",
                "your whole record, and the spreadsheet export of it",
                "the daily notes describing what you've written down",
                "findings you've already been shown",
            ], id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text("·")
                        .font(Font.Soma.dishNote)
                        .foregroundStyle(Color.inkSoft)
                    Text(line)
                        .font(Font.Soma.dishNote)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var priceRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            // Never hardcoded — StoreKit's localized price is the only
            // correct one, and a wrong currency on a paywall is a rejection.
            Text(subscriptions.product?.displayPrice ?? "—")
                .font(Font.Soma.dish)
                .foregroundStyle(Color.ink)
            Text("a year")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)
            Spacer()
            if trialAvailable {
                Text("14 days free first")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.persimmon)
            }
        }
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Button {
                Task {
                    isWorking = true
                    let entitled = await subscriptions.purchase()
                    isWorking = false
                    if entitled { dismiss() }
                }
            } label: {
                HStack {
                    Spacer()
                    Text(isWorking
                         ? "one moment…"
                         : (trialAvailable ? "start the 14 days" : "subscribe"))
                        .font(Font.Soma.buttonLg)
                        .foregroundStyle(Color.paper)
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .fill(Color.ink)
                )
            }
            .buttonStyle(.plain)
            .disabled(isWorking || subscriptions.product == nil)
            .opacity(subscriptions.product == nil ? 0.5 : 1)

            Button {
                Task {
                    isWorking = true
                    await subscriptions.restore()
                    isWorking = false
                }
            } label: {
                Text("restore a purchase")
                    .font(Font.Soma.margin)
                    .underline()
                    .foregroundStyle(Color.inkSoft)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
    }

    /// Guideline 3.1.2's disclosure, in the app's own voice.
    ///
    /// A paywall for an auto-renewable subscription has to name the thing
    /// being sold, its length, its price, and the fact that it renews on its
    /// own — and it has to say that the free trial becomes a charge. Most of
    /// that was already on this sheet in pieces; what was missing was the
    /// word *renewing*, which is the piece a reader can be surprised by, and
    /// so the piece Apple checks for.
    private var renewalTerms: some View {
        Text(renewalSentence)
            .font(Font.Soma.dishNote)
            .foregroundStyle(Color.inkSoft)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var renewalSentence: String {
        // The price and the name come from StoreKit or not at all — a
        // hardcoded "$15" is wrong in every other storefront, and a wrong
        // price on a paywall is a rejection on its own. When the store is
        // unreachable the sentence drops the price rather than reading
        // "— a year"; the button is disabled in that state anyway.
        let renews: String
        if let product = subscriptions.product {
            renews = "\(product.displayName) — \(product.displayPrice) a year, "
                   + "renewing itself each year until you cancel it in the "
                   + "App Store."
        } else {
            renews = "Somatic, yearly — a subscription that renews each year "
                   + "until you cancel it in the App Store."
        }
        guard trialAvailable else { return renews }
        return renews + " the 14 free days become the first paid year when "
             + "they run out; cancel before then and you're charged nothing."
    }

    /// The two links 3.1.2 requires. The terms open Apple's standard EULA —
    /// the agreement that actually governs the purchase — and privacy opens
    /// the full policy already carried in the app, so neither depends on a
    /// page being reachable at review time.
    private var legalLinks: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            if let terms = SomaFeatures.termsOfUseURL {
                Link(destination: terms) {
                    legalLabel("terms of use")
                }
                Text("·")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.inkSoft)
            }
            Button { showingPrivacy = true } label: {
                legalLabel("privacy policy")
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    private func legalLabel(_ text: String) -> some View {
        Text(text)
            .font(Font.Soma.margin)
            .underline()
            .foregroundStyle(Color.inkSoft)
    }
}
