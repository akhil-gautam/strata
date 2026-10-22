import Foundation

// MARK: - Payload

/// A JSON object returned by one of the service APIs.
///
/// The dictionary is read on the main actor and never mutated, so the
/// sendability check is relaxed deliberately rather than by accident.
struct ServicePayload: @unchecked Sendable {
    let raw: [String: Any]

    init(raw: [String: Any]) {
        self.raw = raw
    }

    func object(_ key: String) -> ServicePayload? {
        guard let dictionary = raw[key] as? [String: Any] else { return nil }
        return ServicePayload(raw: dictionary)
    }

    func array(_ key: String) -> [ServicePayload] {
        guard let items = raw[key] as? [Any] else { return [] }
        return items.compactMap { $0 as? [String: Any] }.map { ServicePayload(raw: $0) }
    }

    func string(_ key: String) -> String? {
        if let value = raw[key] as? String { return value }
        if let value = raw[key] as? NSNumber { return value.stringValue }
        return nil
    }

    func number(_ key: String) -> Double? {
        if let value = raw[key] as? NSNumber { return value.doubleValue }
        if let value = raw[key] as? Double { return value }
        if let value = raw[key] as? Int { return Double(value) }
        return nil
    }

    func integer(_ key: String) -> Int? {
        number(key).map { Int($0) }
    }

    /// Finds the first number stored under `key`, at any depth.
    ///
    /// These APIs move their numbers around between versions, so the tiles
    /// read what they can find instead of assuming one fixed shape.
    func firstNumber(for key: String) -> Double? {
        if let value = number(key) { return value }
        for value in raw.values {
            if let dictionary = value as? [String: Any],
               let found = ServicePayload(raw: dictionary).firstNumber(for: key) {
                return found
            }
            if let items = value as? [Any] {
                for item in items {
                    guard let dictionary = item as? [String: Any] else { continue }
                    if let found = ServicePayload(raw: dictionary).firstNumber(for: key) { return found }
                }
            }
        }
        return nil
    }
}

// MARK: - API access

/// A thin wrapper over the shared HTTP client.
enum ServiceAPI {
    /// Builds a URL, percent-encoding the query items.
    static func url(_ path: String, query: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: path) else { return nil }
        if !query.isEmpty {
            components.queryItems = query
        }
        return components.url
    }

    /// Fetches a JSON object.
    static func object(_ url: URL, token: String? = nil, headers: [String: String] = [:]) async throws -> ServicePayload {
        let raw = try await HTTPClient.json(url, token: token, headers: headers)
        return ServicePayload(raw: raw)
    }
}

// MARK: - Token entry

/// A token the user pasted, optionally carrying a second value after a colon
/// — an API key plus a channel id, for instance.
struct ServiceTokenEntry {
    var token: String
    var identifier: String?

    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            token = parts[0]
            identifier = parts[1]
        } else {
            token = trimmed
            identifier = nil
        }
    }
}
