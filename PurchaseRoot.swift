//
// Created by Curvachip LLC
//
// Please share any feedback to developer@curvachip.com
//

import SwiftUI
import StoreKit

struct PurchaseRoot: View {
    
    @EnvironmentObject private var purchaseModel: ProductStore
    
    @Environment(\.scenePhase) private var scenePhase
    
    @Binding var isPresented: Bool
    
    @State private var status: Product.SubscriptionInfo.Status?
    @State private var currentSubscription: Product?

    @State private var hideLastFeature: Bool = false
    
    var availableSubscriptions: [Product] {
        if let available = purchaseModel.products[.autoRenewable]?.filter({ $0.id != currentSubscription?.id }) {
            return available
        }
        return []
    }
    
    var body: some View {
        ZStack {
            
            // Call your purchase view here and the alerts will be displayed as an overlay
            PurchaseView(isPresented: $isPresented)
                .overlay(alignment: .top) {
                    if let currentSubscription = currentSubscription, let status = status {
                        SubscriptionStatusView(product: currentSubscription,
                                               status: status)
                        .padding(.top, 50)
                    }
                }
        }
        
        // Every time the subscription status changes, the view is updated
        .onChange(of: status) { newValue in
            Task {
                // This slight delay is necessary to ensure proper rendering of the view
                try await Task.sleep(for: .seconds(0.5))
                await updateSubscriptionStatus()
                print("UPDATE ===> Subscription Status Changed and Subscription Status Updated...")
            }
        }
        // Every time the view becomes active, background, or inactive, the view is updated
        /*
        .onChange(of: scenePhase) { newPhase in
            Task {
                await updateSubscriptionStatus()
                print("UPDATE ===> Scene Phase Changed and Subscription Status Updated...")
            }
        }
         */
        .onAppear {
            Task {
                try await Task.sleep(for: .seconds(0.5))
                await updateSubscriptionStatus()
                print("UPDATE ===> View Appeared and Subscription Status Updated...")
            }
        }
    }
    
    // If Family Sharing purchases a Standard subscription and the user purchases a Premium subscription, for example, this method will assign the highest available product to the user
    @MainActor
    func updateSubscriptionStatus() async {
        do {
            guard let product = purchaseModel.products[.autoRenewable]?.first, let statuses = try await product.subscription?.status else {
                return
            }
            
            var highestStatus: Product.SubscriptionInfo.Status? = nil
            var highestProduct: Product? = nil
            
            for status in statuses {
                switch status.state {
                case .expired, .revoked:
                    continue
                default:
                    let renewalInfo = try purchaseModel.checkVerified(status.renewalInfo)
                    
                    guard let newSubscription = purchaseModel.products[.autoRenewable]?.first(where: { $0.id == renewalInfo.currentProductID }) else {
                        continue
                    }
                    
                    guard let currentProduct = highestProduct else {
                        highestStatus = status
                        highestProduct = newSubscription
                        continue
                    }
                    
                    guard let highestEntitlement = ServiceEntitlement(for: currentProduct), let newEntitlement = ServiceEntitlement(for: newSubscription) else {
                        continue
                    }
                    
                    if newEntitlement > highestEntitlement {
                        highestStatus = status
                        highestProduct = newSubscription
                    }
                }
            }
            
            status = highestStatus
            currentSubscription = highestProduct
            
        } catch {
            print("Failed to update subscription status: \(error)")
        }
    }

}

#Preview {
    PurchaseRoot(isPresented: Binding.constant(true))
        .environmentObject(ProductStore())
}
