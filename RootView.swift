//
// Created by Curvachip LLC
//
// Please share any feedback to developer@curvachip.com
//

import SwiftUI

// Your RootView will generally display the contents of your app for both subscribed and unsubscribed users. You should unlock content by checking the isSubscribed status either through the productStore.isSubscribed, or by re-declaring the AppStorage value here
struct RootView: View {
    
    @State private var showPaywall: Bool = false
    
    @EnvironmentObject var productStore: ProductStore
    
    @State private var celebrationMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            
            // Make sure celebration message is not nil before displaying
            if let celebrationMessage = celebrationMessage {
                Text(celebrationMessage)
                    .foregroundColor(.green)
            }
            
            Text(productStore.isSubscribed ? "You are subscribed to \(productStore.currentSubscription?.displayName ?? "lifetime")!" :"You reached your limit!")
                .multilineTextAlignment(.center)
            
            if !productStore.isSubscribed {
                Button("Upgrade") {
                    showPaywall = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        
        // This purchase entitlements check is important for keeping the subscription status current
        .onChange(of: productStore.currentStatus) { newValue in
            Task {
                await productStore.updateCustomerProductStatus()
            }
            print("UPDATE ===> Root: Subscription Status Changed and Product Status Updated...")
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PurchaseRoot(isPresented: $showPaywall)
                .onDisappear {
                    if productStore.isSubscribed {
                        // Let's celebrate our new user!
                        celebrationMessage = "Welcome Aboard!"
                    }
                }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(ProductStore())
}
