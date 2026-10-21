import Foundation

/// What a `dockdock://` link may ask for. Every verb is safe to repeat and
/// takes no arguments, so a link can never carry a path or a token; anything
/// else is ignored.
enum URLCommand: String, CaseIterable, Sendable {
    case show
    case hide
    case toggle
    case library
    case settings
    case focusStart = "focus/start"
    case focusPause = "focus/pause"
    case refresh

    static let scheme = "dockdock"

    /// `dockdock://toggle`, `dockdock://focus/start`. A trailing slash is
    /// allowed; a query, fragment, user, port or any other part is not.
    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == Self.scheme,
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              let host = parts.host, !host.isEmpty
        else { return nil }
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: true)
        guard path.count <= 1, !parts.path.contains("//") else { return nil }
        let verb = ([host.lowercased()] + path.map { $0.lowercased() }).joined(separator: "/")
        self.init(rawValue: verb)
    }

    /// "dockdock://focus/start".
    var link: String { "\(Self.scheme)://\(rawValue)" }
}
