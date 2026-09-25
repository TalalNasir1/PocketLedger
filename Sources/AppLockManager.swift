import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum AppLockError: LocalizedError {
    case invalidPIN
    case pinsDoNotMatch
    case incorrectPIN
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidPIN: return "Enter exactly four digits."
        case .pinsDoNotMatch: return "The new passcodes do not match."
        case .incorrectPIN: return "The current passcode is incorrect."
        case .keychain(let status): return "The passcode could not be saved securely (Keychain error \(status))."
        }
    }
}

struct PINCredential: Codable, Equatable {
    let salt: Data
    let digest: Data

    static func create(for pin: String) throws -> PINCredential {
        guard AppLockManager.isValidPIN(pin) else { throw AppLockError.invalidPIN }
        var random = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
        guard status == errSecSuccess else { throw AppLockError.keychain(status) }
        let salt = Data(random)
        return PINCredential(salt: salt, digest: digest(for: pin, salt: salt))
    }

    func matches(_ pin: String) -> Bool {
        guard AppLockManager.isValidPIN(pin) else { return false }
        let candidate = Self.digest(for: pin, salt: salt)
        guard candidate.count == digest.count else { return false }
        return zip(candidate, digest).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func digest(for pin: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(pin.utf8))
        return Data(SHA256.hash(data: input))
    }
}

@MainActor
final class AppLockManager: ObservableObject {
    @Published private(set) var hasPasscode: Bool
    @Published private(set) var isLocked: Bool
    @Published var biometricsEnabled: Bool {
        didSet { UserDefaults.standard.set(biometricsEnabled, forKey: Self.biometricsKey) }
    }

    private static let service = "com.personal.pocketledger.applock"
    private static let account = "four-digit-pin"
    private static let biometricsKey = "PocketLedger.UseTouchID"

    init() {
        let configured = Self.loadCredential() != nil
        hasPasscode = configured
        isLocked = configured
        biometricsEnabled = UserDefaults.standard.object(forKey: Self.biometricsKey) as? Bool ?? true
    }

    nonisolated static func isValidPIN(_ pin: String) -> Bool {
        pin.count == 4 && pin.allSatisfy(\.isNumber)
    }

    var biometryName: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return "Touch ID" }
        switch context.biometryType {
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        default: return "Biometrics"
        }
    }

    var canUseBiometrics: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func setPasscode(_ pin: String, confirmation: String) throws {
        guard Self.isValidPIN(pin) else { throw AppLockError.invalidPIN }
        guard pin == confirmation else { throw AppLockError.pinsDoNotMatch }
        try Self.saveCredential(PINCredential.create(for: pin))
        hasPasscode = true
        isLocked = false
    }

    func changePasscode(current: String, new: String, confirmation: String) throws {
        guard verify(current) else { throw AppLockError.incorrectPIN }
        try setPasscode(new, confirmation: confirmation)
    }

    func removePasscode(current: String) throws {
        guard verify(current) else { throw AppLockError.incorrectPIN }
        let status = SecItemDelete(Self.keychainQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppLockError.keychain(status) }
        hasPasscode = false
        isLocked = false
    }

    func unlock(with pin: String) -> Bool {
        guard verify(pin) else { return false }
        isLocked = false
        return true
    }

    func lock() {
        if hasPasscode { isLocked = true }
    }

    func authenticateWithBiometrics() async -> Bool {
        guard hasPasscode, biometricsEnabled else { return false }
        let context = LAContext()
        context.localizedFallbackTitle = "Use passcode"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return false }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock your private Pocket Ledger data"
            )
            if success { isLocked = false }
            return success
        } catch {
            return false
        }
    }

    private func verify(_ pin: String) -> Bool {
        Self.loadCredential()?.matches(pin) == true
    }

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func loadCredential() -> PINCredential? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(PINCredential.self, from: data)
    }

    private static func saveCredential(_ credential: PINCredential) throws {
        let data = try JSONEncoder().encode(credential)
        SecItemDelete(keychainQuery() as CFDictionary)
        var query = keychainQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw AppLockError.keychain(status) }
    }
}
