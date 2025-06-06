//
// Created by Curvachip LLC
//
// Please share any feedback to developer@curvachip.com
//

import SwiftUI
import StoreKit

struct SubscriptionStatusView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var scale: CGFloat = 0.95
    
    let product: Product
    let status: Product.SubscriptionInfo.Status
    
    private struct Format {
        let icon: String
        let message: String
        let button: Bool
        let buttonLabel: String?
        let buttonAction: (() -> Void)?
        let emphasisColor: Color
    }
    
    var body: some View {
        let format = formatForStatus()
        
        HStack(spacing: 8) {
            ZStack(alignment: .center) {
                Circle()
                    .fill(format.emphasisColor.opacity(0.15))
                    .frame(width: 24, height: 24)
                Image(systemName: format.icon)
                    .font(.system(size: 14))
                    .foregroundColor(format.emphasisColor)
                    .bold()
            }
            
            Text(format.message)
                .font(.system(size: 10))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .truncationMode(.tail)
                .bold(format.button)
            
            Spacer()
            
            if format.button, let label = format.buttonLabel {
                Button(label, action: {
                    format.buttonAction?()
                    switch status.state {
                    case .inBillingRetryPeriod, .inGracePeriod, .expired:
                        
                        print("nil")
                    default:
                        break
                    }
                })
                .font(.system(size: 10))
                .bold()
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            /*
            if !format.button {
                Button(action: {
                    withAnimation {
                        // TODO: Dismiss alert
                        
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            */
        }
        .padding(7)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 4)
                    .clipShape(
                        CustomRoundedRectangle(cornerRadius: 2, corners: [.topLeft, .bottomLeft])
                    )
            }
        )
        .padding(.horizontal)
        .scaleEffect(scale)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.67) {
                withAnimation(.easeOut(duration: 0.15)) {
                    scale = 1.05
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        scale = 0.97
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            scale = 1.0
                        }
                    }
                }
            }
            
            switch status.state {
            case .revoked:
                DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                    withAnimation {
                        // TODO: Dismiss alert
                    }
                }
            default:
                break
            }
        }
    }
    
    private func formatForStatus() -> Format {
        guard case .verified(let renewalInfo) = status.renewalInfo,
              case .verified(let transaction) = status.transaction else {
            return Format(
                icon: "exclamationmark.triangle.fill",
                message: "The App Store could not verify your subscription status.",
                button: false,
                buttonLabel: nil,
                buttonAction: nil,
                emphasisColor: .red
            )
        }
        
        switch status.state {
        case .subscribed:
            return Format(
                icon: "checkmark.circle.fill",
                message: subscribedDescription(),
                button: false,
                buttonLabel: nil,
                buttonAction: nil,
                emphasisColor: .green
            )
        case .expired:
            if let expirationDate = transaction.expirationDate,
               let expirationReason = renewalInfo.expirationReason {
                return Format(
                    icon: "xmark.circle.fill",
                    message: expirationDescription(expirationReason, expirationDate: expirationDate),
                    button: true,
                    buttonLabel: "Renew",
                    buttonAction: {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    },
                    emphasisColor: .red
                )
            }
        case .revoked:
            if let revokedDate = transaction.revocationDate {
                return Format(
                    icon: "exclamationmark.triangle.fill",
                    message: "The App Store refunded your subscription to \(product.displayName) on \(revokedDate.formattedDate()).",
                    button: false,
                    buttonLabel: nil,
                    buttonAction: nil,
                    emphasisColor: .orange
                )
            }
        case .inGracePeriod:
            return Format(
                icon: "hourglass",
                message: gracePeriodDescription(renewalInfo),
                button: true,
                buttonLabel: "Manage",
                buttonAction: {
                    if let url = URL(string: "https://apps.apple.com/account/billing") {
                        UIApplication.shared.open(url)
                    }
                },
                emphasisColor: .yellow
            )
        case .inBillingRetryPeriod:
            return Format(
                icon: "exclamationmark.triangle.fill",
                message: billingRetryDescription(),
                button: true,
                buttonLabel: "Manage",
                buttonAction: {
                    if let url = URL(string: "https://apps.apple.com/account/billing") {
                        UIApplication.shared.open(url)
                    }
                },
                emphasisColor: .yellow
            )
        default:
            return Format(
                icon: "questionmark.circle.fill",
                message: "Unknown subscription status for \(product.displayName).",
                button: false,
                buttonLabel: nil,
                buttonAction: nil,
                emphasisColor: .gray
            )
        }
        
        return Format(
            icon: "questionmark.circle.fill",
            message: "Unknown subscription status for \(product.displayName).",
            button: false,
            buttonLabel: nil,
            buttonAction: nil,
            emphasisColor: .gray
        )
    }
    
    fileprivate func billingRetryDescription() -> String {
        var description = "The App Store could not confirm your billing information for \(product.displayName)."
        description += " Please verify your billing information to resume service."
        return description
    }
    
    fileprivate func gracePeriodDescription(_ renewalInfo: RenewalInfo) -> String {
        var description = "The App Store could not confirm your billing information for \(product.displayName)."
        if let untilDate = renewalInfo.gracePeriodExpirationDate {
            description += " Please verify your billing information to continue service after \(untilDate.formattedDate())."
        }
        return description
    }
    
    fileprivate func subscribedDescription() -> String {
        return "You are currently subscribed to \(product.displayName)."
    }
    
    fileprivate func expirationDescription(_ expirationReason: RenewalInfo.ExpirationReason, expirationDate: Date) -> String {
        var description = ""
        
        switch expirationReason {
        case .autoRenewDisabled:
            if expirationDate > Date() {
                description += "Your subscription to \(product.displayName) will expire on \(expirationDate.formattedDate())."
            } else {
                description += "Your subscription to \(product.displayName) expired on \(expirationDate.formattedDate())."
            }
        case .billingError:
            description = "Your subscription to \(product.displayName) was not renewed due to a billing error."
        case .didNotConsentToPriceIncrease:
            description = "Your subscription to \(product.displayName) was not renewed due to a price increase that you disapproved."
        case .productUnavailable:
            description = "Your subscription to \(product.displayName) was not renewed because the product is no longer available."
        default:
            description = "Your subscription to \(product.displayName) was not renewed."
        }
        
        return description
    }
}

extension Date {
    func formattedAlertDate() -> String {
        return formatted(date: .abbreviated, time: .shortened)
    }
}

struct CustomRoundedRectangle: Shape {
    let cornerRadius: CGFloat
    let corners: UIRectCorner
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
        )
        return Path(path.cgPath)
    }
}
