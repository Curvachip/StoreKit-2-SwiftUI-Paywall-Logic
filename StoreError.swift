//
// Created by Curvachip LLC
//
// Please share any feedback to developer@curvachip.com
//

import Foundation
import StoreKit

public enum StoreError: Error, LocalizedError {
    case failedVerification(Error)
    case invalidProductIdentifiers([String])
    case productRequestFailed(Error)
    case networkError
    case purchaseFailed(String)
    case restoreFailed(String)
    case userCancelled
    case productNotFound
    case unknown(Error)
    case notEntitled
    case systemError(String)
    case notAvailableInStorefront
    case unsupported        // iOS 18+, macOS 15+
    case purchasePending
    
    public init(_ error: Error) {
        if let skError = error as? StoreKitError {
            switch skError {
            case .unknown:
                self = .unknown(skError)
            case .userCancelled:
                self = .userCancelled
            case .networkError:
                self = .networkError
            case .systemError(let underlying):
                self = .systemError(underlying.localizedDescription)
            case .notAvailableInStorefront:
                self = .notAvailableInStorefront
            case .notEntitled:
                self = .notEntitled
            case .unsupported:
                if #available(iOS 18.4, macOS 15.4, tvOS 18.4, watchOS 11.4, visionOS 2.4, *) {
                    self = .unsupported
                } else {
                    self = .unknown(skError)
                }
            @unknown default:
                self = .unknown(skError)
            }
        } else {
            self = .unknown(error)
        }
    }
    
    public var errorDescription: String? {
        switch self {
        case .failedVerification(let error):
            return "Transaction verification failed: \(error.localizedDescription)."
        case .invalidProductIdentifiers(let ids):
            return "Invalid product identifiers: \(ids.joined(separator: ", "))"
        case .productRequestFailed(let error):
            return "Failed to load products: \(error.localizedDescription)"
        case .networkError:
            return "A network error occurred. Please check your connection and try again."
        case .purchaseFailed(let message):
            return "Purchase failed: \(message)"
        case .restoreFailed(let message):
            return "\(message)"
        case .userCancelled:
            return "Purchase was cancelled by the user."
        case .productNotFound:
            return "The requested product could not be found."
        case .unknown(let error):
            return "An unknown error occurred: \(error.localizedDescription)"
        case .notEntitled:
            return "You are not entitled to this product."
        case .systemError(let message):
            return "A system error occurred: \(message)"
        case .notAvailableInStorefront:
            return "This product is not available in your region."
        case .unsupported:
            return "This operation is not supported on your device or OS version."
        case .purchasePending:
            return "Your purchase is still pending approval."
        }
    }
    
    public var title: String {
        switch self {
        case .failedVerification:
            return "Verification Error"
        case .invalidProductIdentifiers:
            return "Invalid Products"
        case .productRequestFailed:
            return "Product Request Error"
        case .networkError:
            return "Network Error"
        case .purchaseFailed:
            return "Purchase Error"
        case .restoreFailed:
            return "Restore Error"
        case .userCancelled:
            return "Cancelled"
        case .productNotFound:
            return "Product Not Found"
        case .unknown:
            return "Unknown Error"
        case .notEntitled:
            return "Entitlement Error"
        case .systemError:
            return "System Error"
        case .notAvailableInStorefront:
            return "Region Error"
        case .unsupported:
            return "Unsupported"
        case .purchasePending:
            return "Pending Purchase"
        }
    }
    
    public var isRetryable: Bool {
        switch self {
        case .purchaseFailed, .productRequestFailed, .systemError, .networkError:
            return true
        default:
            return false
        }
    }
}
