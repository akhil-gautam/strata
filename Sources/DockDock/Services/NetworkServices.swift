import Foundation
import Observation
import Security

/// Credentials for the service tiles, kept in the login keychain: one generic
/// password per provider under ``TokenVault/service``.
///
/// The keychain is only touched by ``TokenVault``, off the main actor: a
/// locked keychain or a changed signature can raise a system prompt, and
/// `SecItem*` blocks until it is answered. This store is the main-actor cache
/// the tiles read; it changes only once the keychain has agreed.
@MainActor
@Observable
final class TokenStore {
    static let shared = TokenStore()

    private(set) var tokens: [String: String] = [:]
    /// False until the launch read of the keychain finishes. Until then every
    /// token reads as missing, which the tiles show as not yet connected.
    private(set) var isLoaded = false
    /// Why the last save or removal for a provider failed; cleared by the
    /// next one that succeeds.
    private(set) var errors: [String: String] = [:]

    private let vault = TokenVault()
    /// Providers saved or removed since launch: the launch read, which may
    /// finish later, must not bring back their old value.
    private var edited: Set<String> = []
    /// Saves run one after another, in the order the user made them.
    private var lastWrite: Task<Void, Never>?

    init() {
        Task { [weak self, vault] in
            let loaded = await vault.loadMigratingDefaults()
            guard let self else { return }
            for (provider, token) in loaded where !self.edited.contains(provider) {
                self.tokens[provider] = token
            }
            self.isLoaded = true
        }
    }

    func token(for provider: String) -> String? {
        guard let token = tokens[provider], !token.isEmpty else { return nil }
        return token
    }

    /// Saves a token, or removes it when `value` is blank. The cache follows
    /// once the keychain write succeeds; a failure lands in ``errors``.
    func set(_ value: String, for provider: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let token: String? = trimmed.isEmpty ? nil : trimmed
        let previous = lastWrite
        lastWrite = Task { [weak self, vault] in
            await previous?.value
            let failure = await vault.store(token, for: provider)
            guard let self else { return }
            if let failure {
                self.errors[provider] = failure
                return
            }
            self.errors[provider] = nil
            self.edited.insert(provider)
            self.tokens[provider] = token
        }
    }
}

/// The only code that touches the token keychain items or the UserDefaults
/// copy older builds kept. Runs on the shared concurrent pool, never on main.
actor TokenVault {
    static let service = "app.dockdock.DockDock.tokens"
    /// Where tokens lived before the keychain.
    private static let legacyDefaultsKey = "serviceTokens"

    /// Every stored token, after moving any left in UserDefaults by earlier
    /// builds into the keychain. A token that fails to move is still returned
    /// and stays in UserDefaults, so the next launch tries again.
    func loadMigratingDefaults() -> [String: String] {
        var tokens = Self.readAll()
        guard UserDefaults.standard.object(forKey: Self.legacyDefaultsKey) != nil else { return tokens }
        var failed: [String: String] = [:]
        for (provider, token) in Self.legacyTokens() where !token.isEmpty {
            // A token already in the keychain was saved later; keep it.
            if tokens[provider] != nil { continue }
            tokens[provider] = token
            if Self.write(token, for: provider) != nil {
                failed[provider] = token
            }
        }
        Self.saveLegacy(failed)
        return tokens
    }

    /// Writes or (for `nil`) deletes a token. Returns why it failed, or `nil`.
    func store(_ token: String?, for provider: String) -> String? {
        let failure = token.map { Self.write($0, for: provider) } ?? Self.delete(provider)
        if failure == nil {
            // The user's choice replaces any copy a failed migration left,
            // so a later launch can't bring the old token back.
            var legacy = Self.legacyTokens()
            if legacy.removeValue(forKey: provider) != nil {
                Self.saveLegacy(legacy)
            }
        }
        return failure
    }

    // MARK: - UserDefaults (legacy)

    private static func legacyTokens() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: legacyDefaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    /// Keeps the tokens still to migrate; drops the key once none are left.
    private static func saveLegacy(_ tokens: [String: String]) {
        let defaults = UserDefaults.standard
        if tokens.isEmpty {
            defaults.removeObject(forKey: legacyDefaultsKey)
        } else if let data = try? JSONEncoder().encode(tokens) {
            defaults.set(data, forKey: legacyDefaultsKey)
        }
    }

    // MARK: - Keychain

    private static func readAll() -> [String: String] {
        // The file-based login keychain can't return data for a match-all
        // query, so list the accounts first and read each one.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            if status != errSecItemNotFound {
                NSLog("DockDock: listing service tokens failed: %@", message(status))
            }
            return [:]
        }
        var tokens: [String: String] = [:]
        for item in items {
            guard let provider = item[kSecAttrAccount as String] as? String,
                  let token = read(provider)
            else { continue }
            tokens[provider] = token
        }
        return tokens
    }

    private static func read(_ provider: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            NSLog("DockDock: reading the %@ token failed: %@", provider, message(status))
            return nil
        }
        guard let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    /// Returns why the write failed, or `nil`.
    private static func write(_ token: String, for provider: String) -> String? {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
        ]
        let data = Data(token.utf8)
        var status = SecItemUpdate(item as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = item
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            add[kSecAttrLabel as String] = "DockDock \(provider) token"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            let reason = message(status)
            NSLog("DockDock: saving the %@ token failed: %@", provider, reason)
            return reason
        }
        return nil
    }

    /// Returns why the removal failed, or `nil`.
    private static func delete(_ provider: String) -> String? {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
        ]
        let status = SecItemDelete(item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            let reason = message(status)
            NSLog("DockDock: removing the %@ token failed: %@", provider, reason)
            return reason
        }
        return nil
    }

    private static func message(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}

/// Minimal async HTTP client for the service tiles.
enum HTTPClient {
    struct Error: Swift.Error, LocalizedError {
        let message: String
        var statusCode: Int? = nil

        var errorDescription: String? { message }
    }

    static func get(_ url: URL, token: String? = nil, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Error(message: "No response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Error(message: "HTTP \(http.statusCode)", statusCode: http.statusCode)
        }
        return data
    }

    static func json(_ url: URL, token: String? = nil, headers: [String: String] = [:]) async throws -> [String: Any] {
        let data = try await get(url, token: token, headers: headers)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Error(message: "Unexpected response")
        }
        return object
    }
}
