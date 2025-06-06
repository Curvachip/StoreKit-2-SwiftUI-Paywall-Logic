//
// Created by Curvachip LLC
//
// Please share any feedback to developer@curvachip.com
//

import SwiftUI
import StoreKit

typealias Transaction = StoreKit.Transaction
typealias RenewalInfo = StoreKit.Product.SubscriptionInfo.RenewalInfo
typealias RenewalState = StoreKit.Product.SubscriptionInfo.RenewalState

public enum ServiceEntitlement: Int, Comparable {
    case notEntitled = 0
    case weekly = 1
    case yearly = 2
    
    init?(for product: Product) {
        guard let subscription = product.subscription else { return nil }
        self.init(rawValue: subscription.groupLevel)
    }
    
    public static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue > rhs.rawValue
    }
}

struct ProductIDTracker {
    
    // Depending on how your StoreKit naming scheme works, just create the standard prefix for your product ids and add on the raw value of the duration (i.e., if prefix = example, then add raw duration value of yearly, and you get example_yearly)
    static let prefix = "example"
    
    enum Duration: String, CaseIterable {
        case daily
        case weekly
        case monthly
        case yearly
        case lifetime
    }
    
    static func id(for duration: Duration) -> String {
        return "\(prefix)_\(duration.rawValue)"
    }
    
    static var all: [String] {
        Duration.allCases.map { id(for: $0) }
    }
}

class ProductStore: ObservableObject {
    @Published private(set) var products: [StoreProductType: [Product]] = [.consumable: [], .nonConsumable: [], .autoRenewable: [], .nonRenewable: []]
    @Published private(set) var purchasedProducts: [StoreProductType: [Product]] = [.consumable: [], .nonConsumable: [], .autoRenewable: [], .nonRenewable: []]
    @Published private(set) var subscriptionGroupStatus: [String: Product.SubscriptionInfo.Status] = [:]
    @Published private(set) var productDetails: [PurchaseProductDetails] = []
    @Published var purchaseStatus: PurchaseStatus?
    @Published private(set) var isFetchingProducts: Bool = false
    
    @Published var activeError: StoreError?
    
    @Published var subscriptionStatus: Product.SubscriptionInfo.Status?
        
    @Published var currentSubscription: Product?

    @Published var currentStatus: Product.SubscriptionInfo.Status?
    
    //@AppStorage("hasIntro") private var hasIntro = true
    @AppStorage("isSubscribed") var isSubscribed = false
    
    private var updateListenerTask: Task<Void, Never>?
    private let productIdToEmoji: [String: String]
    
    // Optional properties for use in switch statement
    //@Published private var product: Product?
    //@Published private var status: Product.SubscriptionInfo.Status?
    
    // This offers a lot of potential if you reference your app name frequently across your app as it can be changed in one place
    @Published private(set) var appName: String = "Example"
    
    
    init() {
        productIdToEmoji = ProductStore.loadProductIdToEmojiData()
        updateListenerTask = listenForTransactions()
        
        // Initialize as nil since values are set asynchronously
        //product = nil
        //status = nil
        currentSubscription = nil
        currentStatus = nil
        
        Task { await initializeStore() }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    static func loadProductIdToEmojiData() -> [String: String] {
        guard let path = Bundle.main.path(forResource: "Products", ofType: "plist"),
              let plist = FileManager.default.contents(atPath: path),
              let data = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: String] else {
            print("Products.plist missing or unreadable.")
            return [:]
        }
        return data
    }
    
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                print("Received transaction update: \(result)")
                await self.handleTransactionUpdate(result)
            }
        }
    }
    
    @MainActor
    func initializeStore() async {
        await fetchProductDetails()
        await updateCustomerProductStatus()
        //await refreshIntroOfferEligibility()
        print("Store initialization completed")
    }
    
    @MainActor
    func fetchProductDetails() async {
        isFetchingProducts = true
        defer { isFetchingProducts = false }
        
        do {
            let storeProducts = try await Product.products(for: productIdToEmoji.keys)
            var newProducts: [StoreProductType: [Product]] = [.consumable: [], .nonConsumable: [], .autoRenewable: [], .nonRenewable: []]
            var details: [PurchaseProductDetails] = []
            
            for product in storeProducts {
                newProducts[product.storeProductType, default: []].append(product)
                
                let detail = await createProductDetails(for: product)
                details.append(detail)
            }
            
            products = newProducts.mapValues { $0.sorted(by: { $0.price < $1.price }) }
            productDetails = details.sorted { $0.sortOrder < $1.sortOrder }
        } catch let error as StoreKitError {
            let storeError: StoreError
            switch error {
            case .networkError:
                storeError = .networkError
            default:
                storeError = .productRequestFailed(error)
            }
            handleError(storeError)
            
        } catch {
            handleError(error)
        }
    }
    
    
    @MainActor
    private func createProductDetails(for product: Product) async -> PurchaseProductDetails {
        let introOffer = product.subscription?.introductoryOffer
        let introOfferDescription = introOffer.map { offer in
            let price = offer.price
            let value = (price as NSDecimalNumber).doubleValue
            let period = offer.period
            let unit = period.unit
            let count = period.value
            
            if value == 0 {
                return "\(count)-\(unit.localizedDescription) Trial"
            } else {
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.locale = product.priceFormatStyle.locale
                let priceString = formatter.string(from: price as NSDecimalNumber) ?? "$\(value)"
                return "\(priceString) for \(count) \(unit.localizedDescription)\(count > 1 ? "s" : "")"
            }
        }
        
        let duration: String
        if let subscription = product.subscription {
            let period = subscription.subscriptionPeriod
            let unit = period.unit
            let count = period.value
            
            // Determine the expected unit based on ProductIDTracker
            let expectedUnit: Product.SubscriptionPeriod.Unit
            if product.id == ProductIDTracker.id(for: .weekly) {
                expectedUnit = .week
            } else if product.id == ProductIDTracker.id(for: .monthly) {
                expectedUnit = .month
            } else if product.id == ProductIDTracker.id(for: .yearly) {
                expectedUnit = .year
            } else if product.id == ProductIDTracker.id(for: .daily) {
                expectedUnit = .day
            } else {
                expectedUnit = unit // Fallback to actual unit if ID doesn't match
            }
            
            // Map (unit, count) to the effective unit, prioritizing expectedUnit
            switch (unit, count, expectedUnit) {
            case (.day, 7, .week):
                duration = Product.SubscriptionPeriod.Unit.week.localizedDescription
            case (.day, 14, .week):
                duration = "2 \(Product.SubscriptionPeriod.Unit.week.localizedDescription)s"
            case (.day, 1, .day):
                duration = Product.SubscriptionPeriod.Unit.day.localizedDescription
            case (.week, 1, .week):
                duration = Product.SubscriptionPeriod.Unit.week.localizedDescription
            case (.month, 1, .month):
                duration = Product.SubscriptionPeriod.Unit.month.localizedDescription
            case (.year, 1, .year):
                duration = Product.SubscriptionPeriod.Unit.year.localizedDescription
            default:
                // Fallback to actual unit and count, with pluralization if needed
                duration = "\(count) \(unit.localizedDescription)\(count > 1 ? "s" : "")"
            }
        } else {
            duration = "one-time"
        }
        
        let rawTitle = product.displayName
        let cleanedTitle = rawTitle.replacingOccurrences(of: "\(appName) Premium ", with: "").trimmingCharacters(in: .whitespaces) + " Plan"
        
        // Check eligibility for this specific product
        let isEligibleForIntro = await eligibleForIntro(product: product)
        
        let hasTrial = isEligibleForIntro && introOffer != nil // Trial available if eligible and offer exists
        let isIntroOfferFree = introOffer.map { offer in
            return hasTrial && (offer.price as NSDecimalNumber).doubleValue == 0
        } ?? false

        let sortOrder: Int = {
            switch product.subscription?.subscriptionPeriod.unit {
            case .year: return 0
            case .month: return 1
            case .week: return 2
            case .day: return 3
            default: return 99
            }
        }()
        
        let hasPurchased = try? await isPurchased(product)
        
        return PurchaseProductDetails(
            price: product.displayPrice,
            rawPrice: (product.price as NSDecimalNumber).doubleValue,
            productId: product.id,
            duration: duration,
            durationPlanName: cleanedTitle,
            hasTrial: hasTrial,
            sortOrder: sortOrder,
            introOfferDescription: introOfferDescription,
            isIntroOfferFree: isIntroOfferFree,
            isFamilyShareable: product.isFamilyShareable, // Add Family Sharing check
            hasPurchased: hasPurchased ?? false
        )
    }
    
    private func eligibleForIntro(product: Product) async -> Bool {
        guard let renewableSubscription = product.subscription else {
            // No renewable subscription is available for this product.
            return false
        }
        if await renewableSubscription.isEligibleForIntroOffer {
            // The product is eligible for an introductory offer.
            return true
        }
        return false
    }
    
    @MainActor
    func purchase(_ product: Product, promotionalOffer: Product.PurchaseOption? = nil) async throws -> Transaction? {
                
        do {
            purchaseStatus = .purchasing
            
            let result = try await product.purchase(options: promotionalOffer.map { [$0] } ?? [])
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateCustomerProductStatus()
                purchaseStatus = .success

                await transaction.finish()
                return transaction
                
            case .userCancelled:
                purchaseStatus = .none
                //throw StoreError.userCancelled
                return nil
                
            case .pending:
                purchaseStatus = .pending
                //throw StoreError.purchasePending
                return nil
                
            @unknown default:
                purchaseStatus = .none
                throw StoreError.purchaseFailed("Unknown purchase result")
            }
        } catch let error as StoreKitError {
            purchaseStatus = .unverified
            let storeError: StoreError
            
            switch error {
            case .networkError:
                storeError = .networkError
            case .unsupported:
                storeError = .unsupported
            case .systemError:
                storeError = .systemError(error.localizedDescription)
            case .userCancelled:
                storeError = .userCancelled
            case .notAvailableInStorefront:
                storeError = .notAvailableInStorefront
            case .notEntitled:
                storeError = .notEntitled
            case .unknown:
                storeError = .purchaseFailed("Unknown StoreKit error.")
            default:
                storeError = StoreError(error)
            }
            
            handleError(storeError)
            throw storeError
        } catch {
            purchaseStatus = .none
            let storeError = StoreError(error)
            handleError(storeError)
            throw storeError
        }
    }
    
    @MainActor
    func handleError(_ error: Error) {
        let storeError = error as? StoreError ?? StoreError(error)
        activeError = storeError
        print("Error occurred: \(storeError.title) - \(storeError.errorDescription ?? "No description")")
    }
    
    func isPurchased(_ product: Product) async throws -> Bool {
        // Determine whether the user purchases a given product.
        switch product.type {
        case .nonRenewable:
            if let nonRenewable = purchasedProducts[.nonRenewable]?.contains(product) {
                return nonRenewable
            } else {
                return false
            }
        case .nonConsumable:
            if let nonConsumable = purchasedProducts[.nonConsumable]?.contains(product) {
                return nonConsumable
            } else {
                return false
            }
        case .autoRenewable:
            if let autoRenewable = purchasedProducts[.autoRenewable]?.contains(product) {
                return autoRenewable
            } else {
                return false
            }
        default:
            return false
        }
    }
    
    // MARK: - Update Status
    @MainActor
    func updateCustomerProductStatus() async {
        var newPurchasedProducts: [StoreProductType: [Product]] = [.consumable: [], .nonConsumable: [], .autoRenewable: [], .nonRenewable: []]
        var newSubscriptionStatus: [String: Product.SubscriptionInfo.Status] = [:]
        var hasValidAutoRenewableSubscription = false
        var hasLifetimeOffer = false
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                switch transaction.productType {
                case .consumable:
                    if let product = products[.consumable]?.first(where: { $0.id == transaction.productID }) {
                        newPurchasedProducts[.consumable, default: []].append(product)
                    }
                    
                case .nonConsumable:
                    if let product = products[.nonConsumable]?.first(where: { $0.id == transaction.productID }) {
                        newPurchasedProducts[.nonConsumable, default: []].append(product)
                        
                        // Careful about declaring a lifetime offer here for the full app as non-consumables may include access to only certain in-app products such as a race car
                        hasLifetimeOffer = true
                    }
                    
                case .nonRenewable:
                    if let product = products[.nonRenewable]?.first(where: { $0.id == transaction.productID }),
                       let expirationDate = Calendar(identifier: .gregorian).date(byAdding: .year, value: 1, to: transaction.purchaseDate),
                       Date() < expirationDate {
                        newPurchasedProducts[.nonRenewable, default: []].append(product)
                    }
                    
                case .autoRenewable:
                    if let product = products[.autoRenewable]?.first(where: { $0.id == transaction.productID }) {
                        
                        if let subscription = product.subscription,
                           let status = try await subscription.status.max(by: { entitlement(for: $0) < entitlement(for: $1) }) {
                            newSubscriptionStatus[subscription.subscriptionGroupID] = status
                            // Update current subscription and status
                            currentSubscription = product
                            currentStatus = status
                            
                            if status.state == .subscribed || status.state == .inGracePeriod {
                                newPurchasedProducts[.autoRenewable, default: []].append(product)
                                hasValidAutoRenewableSubscription = true
                                subscriptionStatus = status
                            }
                        }
                    }
                    
                default:
                    print("Unhandled product type: \(transaction.productType)")
                }
            } catch {
                handleError(StoreError.productRequestFailed(error))
                print("Transaction verification failed: \(error)")
                return
            }
        }
        
        self.purchasedProducts = newPurchasedProducts
        subscriptionGroupStatus = newSubscriptionStatus
        isSubscribed = hasValidAutoRenewableSubscription || hasLifetimeOffer
        subscriptionStatus = currentStatus
    }
    
    
    @MainActor
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            
            do {
                let active = try await checkActiveEntitlements()
                if active.isEmpty {
                    print("No active purchases.")
                    try await Task.sleep(for: .seconds(7))
                    throw StoreError.restoreFailed("Couldn’t find any purchases to restore. Ensure you’re signed into the correct Apple ID in Settings and try again.")
                } else {
                    print("User has active entitlements:")
                    active.forEach { print($0.productID) }
                    
                    purchaseStatus = .restored
                }
            } catch {
                let storeError = error as? StoreError ?? StoreError(error)
                handleError(storeError)
            }
        } catch {
            // User cancelled restore action
            print("Restore failed: \(error.localizedDescription)")
        }
    }
    
    
    func checkActiveEntitlements() async throws -> [Transaction] {
        var activeEntitlements: [Transaction] = []
        
        // Iterate through current entitlements
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                activeEntitlements.append(transaction)
            case .unverified(_, let error):
                // Log unverified transactions
                print("Unverified restored purchase: \(error)")
            }
        }
        
        return activeEntitlements
    }
    
    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        do {
            let transaction = try checkVerified(result)
            await updateCustomerProductStatus()
            await transaction.finish()
        } catch {
            print("Transaction verification failed: \(error)")
            await MainActor.run {
                handleError(error)
            }
        }
    }
    
    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw StoreError.failedVerification(error)
            
        case .verified(let safe):
            return safe
        }
    }
    
    func isEntitled(to product: Product) -> Bool {
        purchasedProducts[product.storeProductType, default: []].contains(where: { $0.id == product.id })
    }
    
    func emoji(for productId: String) -> String {
        productIdToEmoji[productId] ?? "🛒"
    }
    
    func entitlement(for status: Product.SubscriptionInfo.Status) -> ServiceEntitlement {
        if status.state == .expired || status.state == .revoked {
            return .notEntitled
        }
        
        let productID = status.transaction.unsafePayloadValue.productID
        guard let product = products[.autoRenewable]?.first(where: { $0.id == productID }) else {
            return .notEntitled
        }
        return ServiceEntitlement(for: product) ?? .notEntitled
    }
    
    // MARK: - Future Promo Offers
    /*
    func availablePromotionalOffers(for product: Product) async -> [Product.PurchaseOption] {
        guard let subscription = product.subscription else { return [] }
        let offers = subscription.promotionalOffers
        // Note: To use promotional offers, you need server-side validation to provide
        // the offer identifier, signature, nonce, and timestamp. For now, return an empty
        // array as a placeholder. Implement server-side logic to create PurchaseOption.
        return []
        // Example with server-side validation (uncomment and modify when ready):
        /*
         return offers.compactMap { offer in
         // Fetch signature, nonce, and timestamp from your server for this offer
         return nil
         }
         */
    }
    
    // Placeholder for server-side validation (implement as needed)
    private func fetchPromotionalOfferDetails(_ offerId: String) async -> (signature: String, nonce: UUID, timestamp: Int)? {
        // Implement server communication to get promotional offer details
        return nil
    }
     */
}



enum PurchaseStatus: String, CaseIterable {
    case success,
         unverified,
         pending,
         restored,
         refunded,
         purchasing
}


struct PurchaseProductDetails: Identifiable {
    let id = UUID()
    let price: String
    let rawPrice: Double
    let productId: String
    let duration: String
    let durationPlanName: String
    let hasTrial: Bool
    let sortOrder: Int
    let introOfferDescription: String?
    let isIntroOfferFree: Bool
    let isFamilyShareable: Bool // New property
    let hasPurchased: Bool
}

enum StoreProductType: Hashable {
    case consumable
    case nonConsumable
    case autoRenewable
    case nonRenewable
}

extension Product {
    var storeProductType: StoreProductType {
        switch type {
        case .consumable: return .consumable
        case .nonConsumable: return .nonConsumable
        case .autoRenewable: return .autoRenewable
        case .nonRenewable: return .nonRenewable
        default: return .nonConsumable
        }
    }
}

extension Date {
    func formattedDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd, yyyy"
        return dateFormatter.string(from: self)
    }
}
