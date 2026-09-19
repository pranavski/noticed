import Foundation
import OSLog
import StoreKit
import Supabase

/// What the reader is entitled to right now.
///
/// The line this draws is the one decided in
/// `docs/decisions/2026-09-10-positioning-and-pricing.md` §3 and moved by
/// `2026-09-19-subscription-enforcement.md` §1:
/// **descriptions are free, inferences are paid.** Logging, the record,
/// export, deletion and the daily reflections never expire — reflections are
/// pure server-side templating with no model call behind them, so a free
/// account costs nothing to keep honest. What a subscription buys is the
/// nightly engine, and the reading of a meal into ingredients that feeds it.
///
/// Parsing sits on the paid side as of 2026-09-19. It is the per-meal cost
/// and the dominant one; leaving it free meant a lapsed account cost roughly
/// $0.75/month forever against no revenue. A free account still logs
/// everything, in its own words, through the same path a declined-consent
/// account uses — so the record is never blocked, only left unread.
///
/// Insights already surfaced stay readable after a lapse. They were true when
/// they were written and they are the reader's own record; withdrawing them
/// would be taking something back rather than declining to do more work.
enum SubscriptionState: Equatable {
    /// No entitlement, or it lapsed. The notebook still works.
    case free
    /// Inside the introductory free trial.
    case trial(expires: Date?)
    /// Paid and current.
    case subscribed(expires: Date?)

    /// Whether the nightly engine may run for this reader.
    var canGenerateInsights: Bool {
        switch self {
        case .free: return false
        case .trial, .subscribed: return true
        }
    }

    /// Whether a logged meal may be sent to `parse-meal` to be read into
    /// ingredients and ranges. Free accounts file meals as written instead —
    /// see `MealLogger.log`, which routes them down the path a
    /// declined-consent account already takes.
    ///
    /// This is a client-side routing decision, not the gate. `parse-meal`
    /// makes its own, and refuses by filing the meal as written rather than
    /// by erroring.
    var canParseMeals: Bool { canGenerateInsights }

    /// Everything below is free forever and must stay that way. Kept as an
    /// explicit property rather than an implicit truth so that a future gate
    /// added in the wrong place fails a test instead of shipping.
    var canLogMeals: Bool { true }
    var canReadOwnRecord: Bool { true }
    var canExport: Bool { true }
    var canSeeReflections: Bool { true }
    /// Findings already written stay readable. See the type's note.
    var canReadExistingInsights: Bool { true }
}

/// Observes StoreKit entitlements for the yearly subscription.
///
/// StoreKit 2 only: `Transaction.currentEntitlements` is the source of truth
/// and `Transaction.updates` keeps it current across renewals, refunds,
/// family sharing changes and purchases made on another device. There is no
/// receipt parsing and no local expiry arithmetic beyond reading the dates
/// StoreKit already verified.
///
/// **This is a client-side gate and a client-side gate only.** It decides
/// what the app offers, not what the server will do. `parse-meal` and
/// `generate-insights` cost real money per call and are reachable with any
/// valid JWT, so the server has to make its own decision — see the TODO in
/// `docs/deployment-checklist.md`. Treat this type as UI state.
///
/// The one thing here the server genuinely depends on is `appAccountToken`,
/// set on every purchase: it is how Apple's notifications say *which* of our
/// readers a transaction belongs to. See `purchase()`.
@MainActor
final class SubscriptionStore: ObservableObject {

    /// Must match the product created in App Store Connect and the id in
    /// `Noticed.storekit` (the local testing configuration).
    static let yearlyProductID = "com.pranavsurampudi.noticed.yearly"

    @Published private(set) var state: SubscriptionState = .free
    @Published private(set) var product: Product?
    /// True until the first entitlement read completes. The paywall must not
    /// flash at a subscriber during launch, so callers treat "loading" as
    /// "entitled" for presentation purposes only.
    @Published private(set) var isLoading = true
    @Published private(set) var purchaseError: String?

    private var updatesTask: Task<Void, Never>?
    private static let log = Logger(
        subsystem: "com.pranavsurampudi.noticed", category: "subscription"
    )

    /// Resolves the signed-in reader's id for `appAccountToken`. Injected so
    /// a test can drive `purchase()` without a session; the default reads the
    /// same session every repository reads.
    private let currentUserID: @Sendable () async -> UUID?

    init(
        currentUserID: @escaping @Sendable () async -> UUID? = {
            try? await SupabaseClient.shared.auth.session.user.id
        }
    ) {
        self.currentUserID = currentUserID
        #if DEBUG
        // Screenshot and preview runs are always entitled; the paywall has
        // its own preview flag so it can still be captured deliberately.
        if ProcessInfo.processInfo.environment["SOMA_PREVIEW"] == "1" {
            state = .subscribed(expires: nil)
            isLoading = false
            return
        }
        #endif
        updatesTask = Task { [weak self] in
            // Started before the first refresh so a transaction arriving
            // mid-launch is not missed.
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.refresh()
            }
        }
        Task { await refresh() }
    }

    deinit { updatesTask?.cancel() }

    /// Re-reads entitlements and the product. Safe to call repeatedly.
    func refresh() async {
        await loadProduct()
        var latest: SubscriptionState = .free
        for await entitlement in Transaction.currentEntitlements {
            // An unverified entitlement is not an entitlement. StoreKit has
            // already done the signature check; anything it declines to
            // vouch for is ignored rather than trusted optimistically.
            guard case .verified(let transaction) = entitlement else { continue }
            guard transaction.productID == Self.yearlyProductID else { continue }
            if let revoked = transaction.revocationDate {
                Self.log.info("entitlement revoked at \(revoked, privacy: .public)")
                continue
            }
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }

            latest = transaction.offerType == .introductory
                ? .trial(expires: transaction.expirationDate)
                : .subscribed(expires: transaction.expirationDate)
        }
        state = latest
        isLoading = false
    }

    private func loadProduct() async {
        guard product == nil else { return }
        do {
            product = try await Product.products(for: [Self.yearlyProductID]).first
        } catch {
            // Offline, or the product is not configured yet. The paywall
            // shows its copy without a price rather than an error screen —
            // a reader who cannot reach the App Store has not done anything
            // wrong, and the rest of the app still works.
            Self.log.error(
                "product load failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// True when this Apple ID has never used the trial. Drives whether the
    /// paywall may say "14 days free" — claiming a trial someone is not
    /// eligible for is the kind of small lie this app does not tell.
    var isEligibleForTrial: Bool {
        get async {
            guard let subscription = product?.subscription else { return false }
            return await subscription.isEligibleForIntroOffer
        }
    }

    /// Binds the purchase to the signed-in reader.
    ///
    /// `appAccountToken` is the join between Apple's world and ours: Apple
    /// echoes it on the transaction and in every App Store Server
    /// Notification, which is the only way the webhook that writes
    /// entitlement can know whose row to write. Nothing else in a
    /// notification identifies our user.
    ///
    /// **It cannot be applied retroactively.** A transaction bought without
    /// it carries none forever, and no later deploy repairs that — see
    /// `docs/decisions/2026-09-19-subscription-enforcement.md` §5 and §11.
    ///
    /// A missing session should be impossible (every screen is behind sign-in)
    /// but if the session read fails we still let the purchase proceed: taking
    /// someone's money is not what fails here, and the server-side healing
    /// path binds a tokenless transaction by verifying its id against Apple.
    /// Refusing to sell because a keychain read blipped would be the worse
    /// trade.
    private func purchaseOptions() async -> Set<Product.PurchaseOption> {
        guard let userID = await currentUserID() else {
            Self.log.error("purchasing with no appAccountToken — no session")
            return []
        }
        return [.appAccountToken(userID)]
    }

    /// Returns true when the reader ends up entitled. A user cancelling is
    /// not an error and produces no message.
    @discardableResult
    func purchase() async -> Bool {
        guard let product else {
            purchaseError = "the subscription isn't available just now — try again in a moment."
            return false
        }
        purchaseError = nil
        do {
            switch try await product.purchase(options: await purchaseOptions()) {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                await refresh()
                return state.canGenerateInsights
            case .userCancelled:
                return false
            case .pending:
                // Ask to Buy, or a payment awaiting approval. Not a failure;
                // `Transaction.updates` will deliver it if it completes.
                purchaseError = "waiting on approval — it'll unlock on its own if it goes through."
                return false
            @unknown default:
                return false
            }
        } catch {
            Self.log.error("purchase failed: \(String(describing: error), privacy: .public)")
            purchaseError = "that didn't go through. nothing was charged."
            return false
        }
    }

    /// Guideline 3.1.1 requires a restore path that does not depend on the
    /// original device.
    func restore() async {
        do {
            try await AppStore.sync()
            await refresh()
            if !state.canGenerateInsights {
                purchaseError = "nothing to restore on this Apple ID."
            }
        } catch {
            Self.log.error("restore failed: \(String(describing: error), privacy: .public)")
            purchaseError = "couldn't reach the App Store just now."
        }
    }
}
