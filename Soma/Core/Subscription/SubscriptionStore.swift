import Foundation
import OSLog
import StoreKit

/// What the reader is entitled to right now.
///
/// The line this draws is the one decided in
/// `docs/decisions/2026-09-10-positioning-and-pricing.md` §3:
/// **descriptions are free, inferences are paid.** Logging, the record,
/// export, deletion and the daily reflections never expire — reflections are
/// pure server-side templating with no model call behind them, so a free
/// account costs nothing to keep honest. What a subscription buys is the
/// nightly engine: new findings.
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

    init() {
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
            switch try await product.purchase() {
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
