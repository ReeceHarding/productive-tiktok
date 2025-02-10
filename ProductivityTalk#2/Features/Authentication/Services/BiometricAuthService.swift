import LocalAuthentication
import Foundation

enum BiometricType {
    case none
    case touchID
    case faceID
    
    var description: String {
        switch self {
        case .none: return "none"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        }
    }
}

enum BiometricError: LocalizedError {
    case authenticationFailed
    case userCancel
    case userFallback
    case biometryNotAvailable
    case biometryNotEnrolled
    case biometryLockout
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .authenticationFailed: return "Authentication failed"
        case .userCancel: return "User cancelled"
        case .userFallback: return "User chose to use password"
        case .biometryNotAvailable: return "Biometric authentication is not available"
        case .biometryNotEnrolled: return "No biometric authentication methods enrolled"
        case .biometryLockout: return "Biometric authentication is locked out. Please use password"
        case .unknown: return "Unknown error occurred"
        }
    }
}

@MainActor
class BiometricAuthService {
    static let shared = BiometricAuthService()
    private let context = LAContext()
    private let keychainService = "com.productivitytalk.biometric"
    private let defaults = UserDefaults.standard
    
    private init() {
        LoggingService.debug("🔐 BiometricAuthService: Initializing", component: "Authentication")
    }
    
    var biometricType: BiometricType {
        context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .none:
            return .none
        case .touchID:
            return .touchID
        case .faceID:
            return .faceID
        @unknown default:
            return .none
        }
    }
    
    func canUseBiometrics() -> Bool {
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
    
    func authenticateWithBiometrics() async throws {
        LoggingService.debug("🔐 BiometricAuthService: Starting biometric authentication", component: "Authentication")
        
        guard canUseBiometrics() else {
            LoggingService.error("❌ BiometricAuthService: Biometrics not available", component: "Authentication")
            throw BiometricError.biometryNotAvailable
        }
        
        let reason = "Log in with \(biometricType.description)"
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            
            if success {
                LoggingService.success("✅ BiometricAuthService: Authentication successful", component: "Authentication")
            } else {
                LoggingService.error("❌ BiometricAuthService: Authentication failed", component: "Authentication")
                throw BiometricError.authenticationFailed
            }
        } catch let error as LAError {
            LoggingService.error("❌ BiometricAuthService: LAError: \(error.localizedDescription)", component: "Authentication")
            switch error.code {
            case .authenticationFailed:
                throw BiometricError.authenticationFailed
            case .userCancel:
                throw BiometricError.userCancel
            case .userFallback:
                throw BiometricError.userFallback
            case .biometryNotAvailable:
                throw BiometricError.biometryNotAvailable
            case .biometryNotEnrolled:
                throw BiometricError.biometryNotEnrolled
            case .biometryLockout:
                throw BiometricError.biometryLockout
            default:
                throw BiometricError.unknown
            }
        }
    }
    
    func saveBiometricCredentials(email: String, password: String) throws {
        LoggingService.debug("🔐 BiometricAuthService: Saving credentials to keychain", component: "Authentication")
        
        let credentials = "\(email):\(password)".data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecValueData as String: credentials
        ]
        
        // First remove any existing credentials
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            LoggingService.error("❌ BiometricAuthService: Failed to save credentials to keychain", component: "Authentication")
            throw BiometricError.unknown
        }
        
        // Mark that user has enabled biometric login
        defaults.set(true, forKey: "biometricLoginEnabled")
        LoggingService.success("✅ BiometricAuthService: Successfully saved credentials", component: "Authentication")
    }
    
    func retrieveBiometricCredentials() throws -> (email: String, password: String)? {
        LoggingService.debug("🔐 BiometricAuthService: Retrieving credentials from keychain", component: "Authentication")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let credentials = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        let components = credentials.split(separator: ":")
        guard components.count == 2 else { return nil }
        
        LoggingService.success("✅ BiometricAuthService: Successfully retrieved credentials", component: "Authentication")
        return (String(components[0]), String(components[1]))
    }
    
    func removeBiometricCredentials() {
        LoggingService.debug("🔐 BiometricAuthService: Removing credentials from keychain", component: "Authentication")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        
        SecItemDelete(query as CFDictionary)
        defaults.set(false, forKey: "biometricLoginEnabled")
        LoggingService.success("✅ BiometricAuthService: Successfully removed credentials", component: "Authentication")
    }
    
    var isBiometricLoginEnabled: Bool {
        return defaults.bool(forKey: "biometricLoginEnabled")
    }
} 