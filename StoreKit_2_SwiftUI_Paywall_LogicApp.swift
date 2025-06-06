//
// Created by Curvachip LLC
//
// Please share any feedback to developer@curvachip.com
//

import SwiftUI

@main
struct StoreKit_2_SwiftUI_Paywall_LogicApp: App {
    
    @StateObject private var purchaseModel = ProductStore() // ← Important: Use @StateObject now
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color.accentColor)
                .environmentObject(purchaseModel)
        }
    }
}
