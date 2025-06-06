//
// Created by Curvachip LLC
//
// Please share any feedback to developer@curvachip.com
//

import SwiftUI

struct PurchaseView: View {
    
    @Binding var isPresented: Bool
    
    @State private var selectedProductID: String = ProductIDTracker.id(for: .yearly)
    @State private var isPurchasing: Bool = false
    
    @EnvironmentObject private var productStore: ProductStore
    
    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Spacer()
                    Button {
                        isPresented.toggle()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                Spacer()
            }
            .padding()
            
            Text(productStore.purchaseStatus == .purchasing ? "Purchasing..." : "Choose a Plan")
            
            productOptions
            .padding(.bottom)
        }
        
        .onChange(of: productStore.isSubscribed) { isSubscribed in
            if isSubscribed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Dismiss the paywall when the purchase is completed
                    isPresented = false
                }
            }
        }
        .alert(
            productStore.activeError?.title ?? "Error",
            isPresented: Binding(
                get: { productStore.activeError != nil },
                set: { _ in productStore.activeError = nil }
            ),
            presenting: productStore.activeError
        ) { error in
            
            let cancelLabel = Binding(
                get: {
                    switch error {
                    case .purchaseFailed, .productRequestFailed, .networkError, .systemError:
                        return "Cancel" // Two buttons: action + cancel
                    default:
                        return "OK" // Only cancel button
                    }
                },
                set: { _ in } // No-op, as cancelLabel is read-only here
            )
            
            if case .purchaseFailed = error {
                Button("Retry") {
                    Task {
                        await purchaseSelectedProduct()
                    }
                }
            }
            if case .productRequestFailed = error {
                Button("Retry") {
                    Task {
                        await productStore.fetchProductDetails()
                    }
                }
            }
            if case .networkError = error {
                Button("Check Network") {
                    // Open Settings or provide guidance
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            if case .systemError = error {
                Button("Contact Support") {
                    // Open support link or email
                    if let url = URL(string: "https://example.com/contact") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            
            Button(cancelLabel.wrappedValue, role: .cancel) {}
            
        } message: { error in
            Text(error.errorDescription ?? "An unknown error occurred.")
        }
    }
    
    // MARK: - Logic
    
    // Helper to check if this specific product is subscribed
    private func isProductSubscribed(_ productId: String) -> Bool {
        guard productStore.isSubscribed, let currentProductId = productStore.currentSubscription?.id else {
            return false
        }
        return productId == currentProductId
    }
    
    // Complete a purchase by calling this method
    private func purchaseSelectedProduct() async {
        // Search across all product types in the products dictionary
        guard let product = productStore.products.values
            .flatMap( { $0 } ) // Flatten the array of products from all types
            .first(where: { $0.id == selectedProductID }) else {
            return
        }
        
        do {
            // Since promotional offers require server-side validation, pass nil for now
            _ = try await productStore.purchase(product, promotionalOffer: nil)
        } catch {
            // Error handling is managed by ProductStore
        }
    }
    
    // MARK: UI-Components
    
    private var productOptions: some View {
        VStack {
            Spacer()
            
            let productDetails = productStore.productDetails
            
            ForEach(productDetails) { productDetail in
                VStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15)
                            .frame(height: 60)
                            .foregroundStyle(isProductSubscribed(productDetail.productId) ? Color.green.opacity(0.3) : Color.secondary.opacity(0.2))
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(productDetail.introOfferDescription ?? productDetail.durationPlanName)")
                                    .bold()
                                
                                // Pricing information adapts to the region
                                Text("\(productDetail.hasTrial ? "then" : "") \(productDetail.price) per \(productDetail.duration.localizedLowercase)")
                            }
                            
                            Spacer()
                            
                            // Only displayed if purchase shareable with family
                            if productDetail.isFamilyShareable {
                                Image(systemName: "person.3.fill")
                            }
                            
                            Button("Buy") {
                                Task {
                                    // Make sure to assign the correct product id before initiating the purchase
                                    selectedProductID = productDetail.productId
                                    await purchaseSelectedProduct()
                                }
                            }
                            .disabled(isProductSubscribed(productDetail.productId))
                        }
                        .padding(.horizontal)
                    }
                    
                }
                .padding(.horizontal)
            }
        }
    }
}

#Preview {
    PurchaseView(isPresented: Binding.constant(true))
        .environmentObject(ProductStore())
}
