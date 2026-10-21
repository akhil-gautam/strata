import AppKit
import Observation
import SwiftUI

/// The Social, Finance, Stocks and Analytics sections, plus the org-level
/// Claude Usage tile of the AI Usage section.
///
/// Tile ids: `"x"`, `"tiktok"`, `"youtube"` (Social); `"polar"`, `"stripe"`
/// (Finance); `"stock"`, `"stock-chart"`, `"stock-watchlist"` (Stocks);
/// `"datafast"`, `"datafast-chart"`, `"cursor-usage"` (Analytics);
/// `"claude-usage"` (AI Usage).
///
/// Service tiles read their credentials from ``TokenStore``. Until an account
/// is connected the library shows the video's sample values and the bar shows
/// a "Connect" state that opens the tile's settings popover, where the token
/// is entered. Stocks need no account: quotes come from Yahoo Finance.
@MainActor
enum BusinessTiles {
    static let specs: [TileSpec] = [
        service(id: "x", title: "X", category: .social, account: .x, feed: BusinessFeeds.x) {
            AnyView(BusinessSocialTile(account: .x, feed: BusinessFeeds.x, caption: "followers"))
        },
        service(id: "tiktok", title: "TikTok", category: .social, account: .tiktok, feed: BusinessFeeds.tiktok) {
            AnyView(BusinessSocialTile(account: .tiktok, feed: BusinessFeeds.tiktok, caption: "followers"))
        },
        service(id: "youtube", title: "YouTube", category: .social, account: .youtube, feed: BusinessFeeds.youtube) {
            AnyView(BusinessSocialTile(account: .youtube, feed: BusinessFeeds.youtube, caption: "subscribers"))
        },
        service(id: "polar", title: "Polar", category: .finance, account: .polar, feed: BusinessFeeds.polar) {
            AnyView(BusinessRevenueTile(account: .polar, feed: BusinessFeeds.polar))
        },
        service(id: "stripe", title: "Stripe", category: .finance, account: .stripe, feed: BusinessFeeds.stripe) {
            AnyView(BusinessRevenueTile(account: .stripe, feed: BusinessFeeds.stripe))
        },
        stock(id: "stock", title: "Stock", symbolsKey: BusinessStockKeys.stock, defaults: ["AAPL"]) {
            AnyView(BusinessStockTile())
        },
        stock(id: "stock-chart", title: "Stock Chart", symbolsKey: BusinessStockKeys.chart, defaults: ["AAPL"]) {
            AnyView(BusinessStockChartTile())
        },
        stock(
            id: "stock-watchlist",
            title: "Stock Watchlist",
            symbolsKey: BusinessStockKeys.watchlist,
            defaults: BusinessStockKeys.watchlistDefaults
        ) {
            AnyView(BusinessStockWatchlistTile())
        },
        service(
            id: "datafast",
            title: "DataFast",
            category: .analytics,
            account: .datafast,
            refresh: {
                BusinessFeeds.dataFastNow.refresh()
                BusinessFeeds.dataFastWeek.refresh()
            },
            extra: { AnyView(BusinessDataFastModePicker()) }
        ) {
            AnyView(BusinessDataFastTile())
        },
        service(
            id: "datafast-chart",
            title: "DataFast Chart",
            category: .analytics,
            account: .datafast,
            feed: BusinessFeeds.dataFastWeek
        ) {
            AnyView(BusinessDataFastChartTile())
        },
        service(
            id: "claude-usage",
            title: "Claude Usage",
            category: .aiUsage,
            account: .anthropic,
            feed: BusinessFeeds.claude
        ) {
            AnyView(BusinessClaudeUsageTile())
        },
        service(
            id: "cursor-usage",
            title: "Cursor Usage",
            category: .analytics,
            account: .cursor,
            feed: BusinessFeeds.cursor
        ) {
            AnyView(BusinessCursorUsageTile())
        },
    ]

    // MARK: Spec builders

    private static func service<Value: Sendable>(
        id: String,
        title: String,
        category: TileCategory,
        account: BusinessAccount,
        feed: BusinessFeed<Value>,
        extra: (@MainActor () -> AnyView)? = nil,
        make: @escaping @MainActor () -> AnyView
    ) -> TileSpec {
        service(
            id: id,
            title: title,
            category: category,
            account: account,
            refresh: { feed.refresh() },
            extra: extra,
            make: make
        )
    }

    private static func service(
        id: String,
        title: String,
        category: TileCategory,
        account: BusinessAccount,
        refresh: @escaping @MainActor () -> Void,
        extra: (@MainActor () -> AnyView)? = nil,
        make: @escaping @MainActor () -> AnyView
    ) -> TileSpec {
        TileSpec(
            id: id,
            title: title,
            category: category,
            menu: [
                .customize("\(account.title) Account…"),
                .action("Refresh", refresh),
                .action("Open \(account.title)") { account.openDashboard() },
            ],
            settings: TileSettings(
                symbol: account.symbol,
                badge: nil,
                content: { AnyView(BusinessAccountSettings(account: account, extra: extra?())) }
            ),
            make: make
        )
    }

    private static func stock(
        id: String,
        title: String,
        symbolsKey: String,
        defaults: [String],
        make: @escaping @MainActor () -> AnyView
    ) -> TileSpec {
        let symbols: @MainActor () -> [String] = {
            BusinessStockKeys.symbols(UserDefaults.standard.string(forKey: symbolsKey), defaults: defaults)
        }
        return TileSpec(
            id: id,
            title: title,
            category: .stocks,
            menu: [
                .customize(defaults.count > 1 ? "Edit Watchlist…" : "Change Symbol…"),
                .action("Refresh") { BusinessStockQuotes.shared.refresh(symbols()) },
                .action("Open on Yahoo Finance") {
                    let path = symbols().count == 1 ? "quote/\(symbols()[0])" : "portfolios"
                    if let url = URL(string: "https://finance.yahoo.com/\(path)") {
                        NSWorkspace.shared.open(url)
                    }
                },
            ],
            settings: TileSettings(
                symbol: "chart.line.uptrend.xyaxis",
                badge: nil,
                content: {
                    AnyView(BusinessSymbolSettings(key: symbolsKey, defaults: defaults))
                }
            ),
            make: make
        )
    }
}

// MARK: - Accounts

/// A third-party account a tile reads from, keyed into ``TokenStore``.
private enum BusinessAccount: String {
    case x, tiktok, youtube, polar, stripe, datafast, anthropic, cursor

    /// The ``TokenStore`` key.
    var tokenKey: String { rawValue }

    var title: String {
        switch self {
        case .x: "X"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .polar: "Polar"
        case .stripe: "Stripe"
        case .datafast: "DataFast"
        case .anthropic: "Claude"
        case .cursor: "Cursor"
        }
    }

    var symbol: String {
        switch self {
        case .x: "at"
        case .tiktok: "music.note"
        case .youtube: "play.rectangle.fill"
        case .polar: "dollarsign.circle"
        case .stripe: "creditcard.fill"
        case .datafast: "chart.bar.fill"
        case .anthropic: "sparkle"
        case .cursor: "cursorarrow.rays"
        }
    }

    var placeholder: String {
        switch self {
        case .x: "Bearer token:username"
        case .tiktok: "act.…"
        case .youtube: "AIza…:UC…"
        case .polar: "polar_oat_…"
        case .stripe: "rk_live_… or sk_live_…"
        case .datafast: "df_… or dft_…:website id"
        case .anthropic: "sk-ant-admin01-…"
        case .cursor: "key_…"
        }
    }

    var hint: String {
        switch self {
        case .x:
            "An app bearer token from the X developer portal, a colon, then the username to follow."
        case .tiktok:
            "A user access token from TikTok for Developers with the user.info.stats scope."
        case .youtube:
            "A YouTube Data API key, a colon, then the channel id (UC…)."
        case .polar:
            "An organization access token with the metrics:read scope."
        case .stripe:
            "A restricted key with read access to balance transactions."
        case .datafast:
            "A df_ website API key, or a dft_ account token, a colon and the website id."
        case .anthropic:
            "An Admin API key from the Claude Console. Usage and cost are read for the whole organization."
        case .cursor:
            "A team Admin API key from the Cursor dashboard."
        }
    }

    var docs: String {
        switch self {
        case .x: "https://developer.x.com/en/portal/dashboard"
        case .tiktok: "https://developers.tiktok.com/doc/tiktok-api-v2-get-user-info"
        case .youtube: "https://developers.google.com/youtube/v3/getting-started"
        case .polar: "https://polar.sh/docs/integrate/oat"
        case .stripe: "https://dashboard.stripe.com/apikeys"
        case .datafast: "https://datafa.st/docs/api/authentication"
        case .anthropic: "https://platform.claude.com/settings/admin-keys"
        case .cursor: "https://cursor.com/dashboard?tab=settings"
        }
    }

    /// Where "Open …" in the context menu goes.
    @MainActor
    var dashboard: String {
        switch self {
        case .x:
            let user = TokenStore.shared.token(for: tokenKey).flatMap { ServiceTokenEntry($0).identifier }
            return "https://x.com/\(user ?? "")"
        case .tiktok: return "https://www.tiktok.com/profile"
        case .youtube: return "https://studio.youtube.com"
        case .polar: return "https://polar.sh/dashboard"
        case .stripe: return "https://dashboard.stripe.com"
        case .datafast: return "https://datafa.st/dashboard"
        case .anthropic: return "https://platform.claude.com/usage"
        case .cursor: return "https://cursor.com/dashboard"
        }
    }

    @MainActor
    func openDashboard() {
        if let url = URL(string: dashboard) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Feeds

/// One shared, periodically refreshed request per account, so the library
/// preview and the bar tile never fetch twice.
@MainActor
@Observable
private final class BusinessFeed<Value: Sendable> {
    private(set) var value: Value?
    private(set) var failed = false

    @ObservationIgnored let account: BusinessAccount
    @ObservationIgnored private let interval: TimeInterval
    @ObservationIgnored private let fetch: @Sendable (String) async throws -> Value
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var inFlight = false

    init(
        account: BusinessAccount,
        interval: TimeInterval,
        fetch: @escaping @Sendable (String) async throws -> Value
    ) {
        self.account = account
        self.interval = interval
        self.fetch = fetch
    }

    var isConnected: Bool { TokenStore.shared.token(for: account.tokenKey) != nil }

    /// Keeps the value fresh while the calling view is on screen. Restart it
    /// when the token changes (`.task(id: token)`).
    func run() async {
        while !Task.isCancelled {
            await load(force: false)
            guard token != nil else { return }
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }
        }
    }

    func refresh() {
        Task { await load(force: true) }
    }

    private func load(force: Bool) async {
        let current = TokenStore.shared.token(for: account.tokenKey)
        if current != token {
            token = current
            value = nil
            failed = false
            fetchedAt = nil
        }
        guard let current, !inFlight else { return }
        if !force, let fetchedAt, Date().timeIntervalSince(fetchedAt) < interval - 1 { return }

        inFlight = true
        defer { inFlight = false }
        do {
            let result = try await fetch(current)
            guard token == current else { return }
            value = result
            failed = false
        } catch {
            guard token == current else { return }
            failed = true
            NSLog("Shelfie: %@ request failed: %@", account.title, String(describing: error))
        }
        fetchedAt = Date()
    }
}

@MainActor
private enum BusinessFeeds {
    static let x = BusinessFeed(account: .x, interval: 900) { try await BusinessFetch.xFollowers($0) }
    static let tiktok = BusinessFeed(account: .tiktok, interval: 900) { try await BusinessFetch.tiktokFollowers($0) }
    static let youtube = BusinessFeed(account: .youtube, interval: 900) { try await BusinessFetch.youtubeSubscribers($0) }
    static let polar = BusinessFeed(account: .polar, interval: 300) { try await BusinessFetch.polarRevenue($0) }
    static let stripe = BusinessFeed(account: .stripe, interval: 300) { try await BusinessFetch.stripeRevenue($0) }
    static let dataFastNow = BusinessFeed(account: .datafast, interval: 60) { try await BusinessFetch.dataFastNow($0) }
    static let dataFastWeek = BusinessFeed(account: .datafast, interval: 300) { try await BusinessFetch.dataFastWeek($0) }
    static let claude = BusinessFeed(account: .anthropic, interval: 600) { try await BusinessFetch.claudeUsage($0) }
    // Cursor asks integrations to poll its usage events at most hourly.
    static let cursor = BusinessFeed(account: .cursor, interval: 3600) { try await BusinessFetch.cursorUsage($0) }
}

/// What a service tile shows right now.
private enum BusinessPhase<Value> {
    case live(Value)
    /// Not connected, in the library: the video's sample values.
    case sample
    /// Not connected, in the bar.
    case connect
    case loading
    case failed
}

@MainActor
private extension BusinessFeed {
    func phase(in context: TileContext) -> BusinessPhase<Value> {
        if let value { return .live(value) }
        if !isConnected { return context == .library ? .sample : .connect }
        return failed ? .failed : .loading
    }
}

// MARK: - Models

private struct BusinessRevenue: Sendable {
    var amount: Double
    var currency: String
}

private struct BusinessTraffic: Sendable {
    var visitors: Int
    var series: [Double]
}

private struct BusinessClaudeUsage: Sendable {
    var tokens: Int
    var inputTokens: Int
    var cost: Double?
}

private struct BusinessCursorUsage: Sendable {
    var spent: Double
    var requests: Int
    var tokens: Int
}

private struct BusinessFetchError: Error, CustomStringConvertible {
    let description: String
}

// MARK: - Requests

private enum BusinessFetch {
    // MARK: Social

    static func xFollowers(_ entry: String) async throws -> Int {
        let parts = ServiceTokenEntry(entry)
        let user = parts.identifier?.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")) ?? ""
        guard !user.isEmpty,
              let url = ServiceAPI.url(
                  "https://api.x.com/2/users/by/username/\(user)",
                  query: [URLQueryItem(name: "user.fields", value: "public_metrics")]
              )
        else { throw BusinessFetchError(description: "X needs a username after the token") }
        let payload = try await ServiceAPI.object(url, token: parts.token)
        guard let followers = payload.firstNumber(for: "followers_count") else {
            throw BusinessFetchError(description: "No follower count")
        }
        return Int(followers)
    }

    static func tiktokFollowers(_ token: String) async throws -> Int {
        guard let url = ServiceAPI.url(
            "https://open.tiktokapis.com/v2/user/info/",
            query: [URLQueryItem(name: "fields", value: "follower_count")]
        ) else { throw BusinessFetchError(description: "Bad URL") }
        let payload = try await ServiceAPI.object(url, token: token)
        guard let followers = payload.firstNumber(for: "follower_count") else {
            throw BusinessFetchError(description: "No follower count")
        }
        return Int(followers)
    }

    static func youtubeSubscribers(_ entry: String) async throws -> Int {
        let parts = ServiceTokenEntry(entry)
        guard let channel = parts.identifier, !channel.isEmpty,
              let url = ServiceAPI.url(
                  "https://www.googleapis.com/youtube/v3/channels",
                  query: [
                      URLQueryItem(name: "part", value: "statistics"),
                      URLQueryItem(name: "id", value: channel),
                      URLQueryItem(name: "key", value: parts.token),
                  ]
              )
        else { throw BusinessFetchError(description: "YouTube needs a channel id after the key") }
        // The key travels as a query parameter, not as a bearer token.
        let payload = try await ServiceAPI.object(url)
        guard let statistics = payload.array("items").first?.object("statistics"),
              let count = statistics.string("subscriberCount").flatMap({ Int($0) })
        else { throw BusinessFetchError(description: "No subscriber count") }
        return count
    }

    // MARK: Finance

    static func polarRevenue(_ entry: String) async throws -> BusinessRevenue {
        let parts = ServiceTokenEntry(entry)
        let (start, end) = dayRange(days: 30)
        var query = [
            URLQueryItem(name: "start_date", value: start),
            URLQueryItem(name: "end_date", value: end),
            URLQueryItem(name: "interval", value: "day"),
            URLQueryItem(name: "metrics", value: "net_revenue"),
            URLQueryItem(name: "timezone", value: TimeZone.current.identifier),
        ]
        // A personal token needs the organization; an organization token
        // carries it.
        if let organization = parts.identifier, !organization.isEmpty {
            query.append(URLQueryItem(name: "organization_id", value: organization))
        }
        guard let url = ServiceAPI.url("https://api.polar.sh/v1/metrics/", query: query) else {
            throw BusinessFetchError(description: "Bad URL")
        }
        let payload = try await ServiceAPI.object(url, token: parts.token)
        let totals = payload.object("totals")
        guard let cents = totals?.number("net_revenue") ?? totals?.number("revenue") else {
            throw BusinessFetchError(description: "No revenue in the metrics")
        }
        // Polar reports every amount in US cents.
        return BusinessRevenue(amount: cents / 100, currency: "USD")
    }

    static func stripeRevenue(_ key: String) async throws -> BusinessRevenue {
        let since = Int(Date().addingTimeInterval(-30 * 86_400).timeIntervalSince1970)
        // Money moving out to the bank or between accounts is not revenue.
        let excluded: Set<String> = [
            "payout", "payout_cancel", "payout_failure", "payout_minimum_balance_hold",
            "payout_minimum_balance_release", "transfer", "transfer_cancel", "transfer_failure",
            "transfer_refund", "topup", "topup_reversal", "connect_collection_transfer",
        ]
        var net = 0.0
        var currency: String?
        var after: String?
        for _ in 0..<20 {
            var query = [
                URLQueryItem(name: "created[gte]", value: String(since)),
                URLQueryItem(name: "limit", value: "100"),
            ]
            if let after { query.append(URLQueryItem(name: "starting_after", value: after)) }
            guard let url = ServiceAPI.url("https://api.stripe.com/v1/balance_transactions", query: query) else {
                throw BusinessFetchError(description: "Bad URL")
            }
            let page = try await ServiceAPI.object(url, token: key)
            let items = page.array("data")
            for item in items where !excluded.contains(item.string("type") ?? "") {
                net += item.number("net") ?? 0
                if currency == nil { currency = item.string("currency") }
            }
            guard page.raw["has_more"] as? Bool == true, let last = items.last?.string("id") else { break }
            after = last
        }
        let code = (currency ?? "usd").lowercased()
        // Stripe reports minor units, except for zero-decimal currencies.
        let zeroDecimal: Set<String> = ["bif", "clp", "djf", "gnf", "jpy", "kmf", "krw", "mga", "pyg", "rwf", "ugx", "vnd", "vuv", "xaf", "xof", "xpf"]
        return BusinessRevenue(amount: zeroDecimal.contains(code) ? net : net / 100, currency: code.uppercased())
    }

    // MARK: Analytics

    /// `df_` website keys infer the site; `dft_` account tokens carry the
    /// website id after a colon.
    private static func dataFastURL(_ path: String, entry: ServiceTokenEntry, query: [URLQueryItem]) -> URL? {
        var query = query
        if let website = entry.identifier, !website.isEmpty {
            query.append(URLQueryItem(name: "websiteId", value: website))
        }
        return ServiceAPI.url("https://datafa.st/api/v1/analytics/\(path)", query: query)
    }

    static func dataFastNow(_ raw: String) async throws -> Int {
        let entry = ServiceTokenEntry(raw)
        guard let url = dataFastURL("realtime", entry: entry, query: [URLQueryItem(name: "fields", value: "visitors")]) else {
            throw BusinessFetchError(description: "Bad URL")
        }
        let payload = try await ServiceAPI.object(url, token: entry.token)
        guard let visitors = payload.firstNumber(for: "visitors") else {
            throw BusinessFetchError(description: "No realtime visitors")
        }
        return Int(visitors)
    }

    static func dataFastWeek(_ raw: String) async throws -> BusinessTraffic {
        let entry = ServiceTokenEntry(raw)
        let (start, end) = dayRange(days: 7)
        let range = [URLQueryItem(name: "startAt", value: start), URLQueryItem(name: "endAt", value: end)]
        guard let overviewURL = dataFastURL(
            "overview",
            entry: entry,
            query: range + [URLQueryItem(name: "fields", value: "visitors")]
        ), let seriesURL = dataFastURL(
            "timeseries",
            entry: entry,
            query: range + [
                URLQueryItem(name: "fields", value: "visitors"),
                URLQueryItem(name: "interval", value: "hour"),
                URLQueryItem(name: "limit", value: "1000"),
            ]
        ) else { throw BusinessFetchError(description: "Bad URL") }

        let token = entry.token
        async let overview = ServiceAPI.object(overviewURL, token: token)
        async let series = try? ServiceAPI.object(seriesURL, token: token)
        guard let visitors = try await overview.firstNumber(for: "visitors") else {
            throw BusinessFetchError(description: "No visitors")
        }
        let points = await series?.array("data").compactMap { $0.number("visitors") } ?? []
        return BusinessTraffic(visitors: Int(visitors), series: points)
    }

    static func claudeUsage(_ key: String) async throws -> BusinessClaudeUsage {
        let headers = ["x-api-key": key, "anthropic-version": "2023-06-01"]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let startString = ISO8601DateFormatter().string(from: start)
        let window = [
            URLQueryItem(name: "starting_at", value: startString),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "7"),
        ]

        async let cost = try? claudeCost(window: window, headers: headers)

        var input = 0.0
        var output = 0.0
        var page: String?
        for _ in 0..<5 {
            var query = window
            if let page { query.append(URLQueryItem(name: "page", value: page)) }
            guard let url = ServiceAPI.url(
                "https://api.anthropic.com/v1/organizations/usage_report/messages",
                query: query
            ) else { throw BusinessFetchError(description: "Bad URL") }
            let payload = try await ServiceAPI.object(url, headers: headers)
            for bucket in payload.array("data") {
                for result in bucket.array("results") {
                    let creation = result.object("cache_creation")
                    input += (result.number("uncached_input_tokens") ?? 0)
                        + (result.number("cache_read_input_tokens") ?? 0)
                        + (creation?.number("ephemeral_5m_input_tokens") ?? 0)
                        + (creation?.number("ephemeral_1h_input_tokens") ?? 0)
                    output += result.number("output_tokens") ?? 0
                }
            }
            guard payload.raw["has_more"] as? Bool == true, let next = payload.string("next_page") else { break }
            page = next
        }
        return BusinessClaudeUsage(tokens: Int(input + output), inputTokens: Int(input), cost: await cost)
    }

    private static func claudeCost(window: [URLQueryItem], headers: [String: String]) async throws -> Double {
        var cents = 0.0
        var page: String?
        for _ in 0..<5 {
            var query = window
            if let page { query.append(URLQueryItem(name: "page", value: page)) }
            guard let url = ServiceAPI.url("https://api.anthropic.com/v1/organizations/cost_report", query: query) else {
                throw BusinessFetchError(description: "Bad URL")
            }
            let payload = try await ServiceAPI.object(url, headers: headers)
            for bucket in payload.array("data") {
                for result in bucket.array("results") {
                    // Decimal strings in cents.
                    cents += result.string("amount").flatMap(Double.init) ?? 0
                }
            }
            guard payload.raw["has_more"] as? Bool == true, let next = payload.string("next_page") else { break }
            page = next
        }
        return cents / 100
    }

    static func cursorUsage(_ key: String) async throws -> BusinessCursorUsage {
        guard let url = URL(string: "https://api.cursor.com/teams/filtered-usage-events") else {
            throw BusinessFetchError(description: "Bad URL")
        }
        let credentials = Data("\(key):".utf8).base64EncodedString()
        let end = Int(Date().timeIntervalSince1970 * 1000)
        let start = end - 7 * 86_400_000

        var cents = 0.0
        var tokens = 0.0
        var counted = 0
        var total: Int?
        for page in 1...10 {
            let body = try JSONSerialization.data(withJSONObject: [
                "startDate": start, "endDate": end, "page": page, "pageSize": 1000,
            ])
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw BusinessFetchError(description: "Bad response") }

            let payload = ServicePayload(raw: raw)
            if total == nil { total = payload.integer("totalUsageEventsCount") }
            let events = payload.array("usageEvents")
            counted += events.count
            for event in events {
                let usage = event.object("tokenUsage")
                cents += event.number("chargedCents") ?? usage?.number("totalCents") ?? 0
                if let usage {
                    tokens += (usage.number("inputTokens") ?? 0) + (usage.number("outputTokens") ?? 0)
                        + (usage.number("cacheWriteTokens") ?? 0) + (usage.number("cacheReadTokens") ?? 0)
                }
            }
            guard payload.object("pagination")?.raw["hasNextPage"] as? Bool == true else { break }
        }
        return BusinessCursorUsage(spent: cents / 100, requests: total ?? counted, tokens: Int(tokens))
    }

    // MARK: Helpers

    /// "yyyy-MM-dd" for the first and last day of the last `days` days,
    /// today included.
    private static func dayRange(days: Int) -> (String, String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        return (formatter.string(from: start), formatter.string(from: today))
    }
}

// MARK: - Stocks

private enum BusinessStockKeys {
    static let stock = "tiles.stock.symbol"
    static let chart = "tiles.stockChart.symbol"
    static let watchlist = "tiles.stockWatchlist.symbols"
    static let watchlistDefaults = ["AAPL", "MSFT", "NVDA"]

    /// Parses a stored, comma-separated symbol list.
    static func symbols(_ stored: String?, defaults: [String]) -> [String] {
        let parsed = (stored ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
        return parsed.isEmpty ? defaults : Array(parsed.prefix(defaults.count))
    }
}

/// Live quotes from Yahoo Finance's keyless chart endpoint, shared by every
/// stock tile and refreshed once a minute.
@MainActor
@Observable
final class BusinessStockQuotes {
    static let shared = BusinessStockQuotes()

    struct Quote: Sendable {
        var symbol: String
        var name: String
        var price: Double
        var previousClose: Double
        /// Today's closes at five-minute intervals.
        var closes: [Double]

        var change: Double { price - previousClose }
        var percent: Double { previousClose == 0 ? 0 : change / previousClose * 100 }
    }

    private(set) var quotes: [String: Quote] = [:]

    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    private static let interval: TimeInterval = 60

    func run(symbols: [String]) async {
        while !Task.isCancelled {
            await load(symbols, force: false)
            do {
                try await Task.sleep(for: .seconds(Self.interval))
            } catch {
                return
            }
        }
    }

    func refresh(_ symbols: [String]) {
        Task { await load(symbols, force: true) }
    }

    private func load(_ symbols: [String], force: Bool) async {
        let now = Date()
        let due = Set(symbols).filter { symbol in
            guard !inFlight.contains(symbol) else { return false }
            guard !force, let last = fetchedAt[symbol] else { return true }
            return now.timeIntervalSince(last) >= Self.interval - 1
        }
        guard !due.isEmpty else { return }
        inFlight.formUnion(due)

        let results = await withTaskGroup(of: (String, Quote?).self) { group in
            for symbol in due {
                group.addTask { (symbol, try? await Self.fetch(symbol)) }
            }
            var collected: [(String, Quote?)] = []
            for await result in group { collected.append(result) }
            return collected
        }
        for (symbol, quote) in results {
            inFlight.remove(symbol)
            fetchedAt[symbol] = Date()
            if let quote { quotes[symbol] = quote }
        }
    }

    private nonisolated static func fetch(_ symbol: String) async throws -> Quote {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = ServiceAPI.url(
                  "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)",
                  query: [URLQueryItem(name: "range", value: "1d"), URLQueryItem(name: "interval", value: "5m")]
              )
        else { throw BusinessFetchError(description: "Bad symbol") }
        let raw = try await HTTPClient.json(url, headers: [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        ])
        guard let result = ServicePayload(raw: raw).object("chart")?.array("result").first,
              let meta = result.object("meta"),
              let price = meta.number("regularMarketPrice")
        else { throw BusinessFetchError(description: "No quote for \(symbol)") }

        let quote = (result.object("indicators")?.raw["quote"] as? [[String: Any]])?.first
        let closes = (quote?["close"] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue } ?? []
        return Quote(
            symbol: meta.string("symbol") ?? symbol,
            name: meta.string("shortName") ?? meta.string("longName") ?? symbol,
            price: price,
            previousClose: meta.number("chartPreviousClose") ?? meta.number("previousClose") ?? price,
            closes: closes
        )
    }
}

// MARK: - Formatting

private enum BusinessFormat {
    /// 12_450 → "12K", 1_234 → "1.2K", 892_000 → "892K", 9_200_000 → "9.2M".
    static func compact(_ value: Int) -> String {
        let units: [(Double, String)] = [(1e9, "B"), (1e6, "M"), (1e3, "K")]
        let number = Double(value)
        for (scale, suffix) in units where abs(number) >= scale {
            let scaled = number / scale
            return abs(scaled) < 9.95
                ? String(format: "%.1f%@", scaled, suffix)
                : "\(Int(scaled.rounded()))\(suffix)"
        }
        return String(value)
    }

    /// "$4,803": revenue reads as in the video whatever the region.
    static func revenue(_ value: BusinessRevenue) -> String {
        value.amount.formatted(
            .currency(code: value.currency)
                .precision(.fractionLength(0))
                .locale(Locale(identifier: "en_US"))
        )
    }

    /// "42,80 US$" in the user's region.
    static func cost(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(fractionDigits)))
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func price(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US")))
    }

    /// "+3.29", "−3.79" with a true minus sign.
    static func signed(_ value: Double) -> String {
        let text = String(format: "%.2f", abs(value))
        return (value < 0 ? "\u{2212}" : "+") + text
    }
}

@MainActor
private enum BusinessPalette {
    static let up = Color(red: 0.27, green: 0.80, blue: 0.53)
    static let down = Color(red: 0.96, green: 0.36, blue: 0.38)
    static let live = Color(red: 0.30, green: 0.85, blue: 0.45)
    /// The dimmer third line; dark ink on light tiles needs more weight to
    /// read at the same distance.
    static var footnote: Color {
        TilePalette.ink.opacity(AppearanceStore.shared.theme.appearance == .light ? 0.42 : 0.26)
    }

    static func trend(_ change: Double) -> Color { change < 0 ? down : up }
}

// MARK: - Shared pieces

/// Value over caption, with an optional live dot and a dimmer third line.
private struct BusinessReadout: View {
    var value: String
    var caption: String
    var captionTint: Color = TilePalette.caption
    var dot: Color?
    var footnote: String?
    var valueSize: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.tileValue(valueSize))
                .foregroundStyle(TilePalette.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                if let dot {
                    Circle().fill(dot).frame(width: 4.5, height: 4.5)
                }
                Text(caption)
                    .font(.tileCaption(8))
                    .foregroundStyle(captionTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            if let footnote {
                Text(footnote)
                    .font(.tileCaption(7.5))
                    .foregroundStyle(BusinessPalette.footnote)
                    .lineLimit(1)
            }
        }
    }
}

/// The provider mark in the top-right corner. In the bar it sits on a glossy
/// blue dot, as in the video.
private struct BusinessBadge: View {
    let account: BusinessAccount
    @Environment(\.tileContext) private var context

    var body: some View {
        HStack(spacing: -3.5) {
            if context == .bar {
                BusinessSphere().frame(width: 16, height: 16)
            }
            BusinessBrandMark(account: account, diameter: 15.5)
        }
    }
}

/// A readout tile with the provider badge: Finance and the Analytics totals.
private struct BusinessServiceShell<Value>: View {
    let account: BusinessAccount
    let width: CGFloat
    let phase: BusinessPhase<Value>
    /// The readout for live data, or for the sample when `value` is nil.
    let readout: @MainActor (Value?) -> BusinessReadout

    var body: some View {
        DockTile(width: width, inset: 7) {
            ZStack(alignment: .topTrailing) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                BusinessBadge(account: account)
                    .padding(.top, 7)
            }
        }
        .modifier(BusinessConnectTap(phase: phase))
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .live(let value):
            readout(value)
        case .sample:
            readout(nil)
        case .connect:
            BusinessReadout(
                value: account.title,
                caption: "Connect",
                captionTint: TilePalette.focus,
                valueSize: width < 120 ? 13 : 15
            )
        case .loading:
            let shape = readout(nil)
            BusinessReadout(value: "—", caption: shape.caption)
        case .failed:
            BusinessReadout(value: "—", caption: "Check token", captionTint: TilePalette.destructive)
        }
    }
}

/// In the bar, an unconnected or failing tile opens its settings on click.
private struct BusinessConnectTap<Value>: ViewModifier {
    let phase: BusinessPhase<Value>
    @Environment(\.openTileSettings) private var openTileSettings

    func body(content: Content) -> some View {
        switch phase {
        case .connect, .failed:
            content
                .contentShape(Rectangle())
                .onTapGesture { openTileSettings() }
        default:
            content
        }
    }
}

// MARK: - Social

private struct BusinessSocialTile: View {
    let account: BusinessAccount
    let feed: BusinessFeed<Int>
    let caption: String

    @Environment(\.tileContext) private var context

    var body: some View {
        let phase = feed.phase(in: context)
        DockTile(width: 121, inset: 6) {
            HStack(spacing: 8) {
                BusinessBrandMark(account: account, diameter: 38)
                readout(phase)
                Spacer(minLength: 0)
            }
        }
        .modifier(BusinessConnectTap(phase: phase))
        .task(id: TokenStore.shared.token(for: account.tokenKey)) { await feed.run() }
    }

    private func readout(_ phase: BusinessPhase<Int>) -> BusinessReadout {
        switch phase {
        case .live(let count):
            BusinessReadout(value: BusinessFormat.compact(count), caption: caption, valueSize: 18)
        case .sample:
            BusinessReadout(value: "12K", caption: caption, valueSize: 18)
        case .connect:
            BusinessReadout(value: account.title, caption: "Connect", captionTint: TilePalette.focus, valueSize: 15)
        case .loading:
            BusinessReadout(value: "—", caption: caption, valueSize: 18)
        case .failed:
            BusinessReadout(value: "—", caption: "Check token", captionTint: TilePalette.destructive, valueSize: 18)
        }
    }
}

// MARK: - Finance

private struct BusinessRevenueTile: View {
    let account: BusinessAccount
    let feed: BusinessFeed<BusinessRevenue>

    @Environment(\.tileContext) private var context

    var body: some View {
        BusinessServiceShell(account: account, width: 131, phase: feed.phase(in: context)) { revenue in
            BusinessReadout(
                value: revenue.map(BusinessFormat.revenue) ?? "$12,450",
                caption: "net revenue · last 30 days"
            )
        }
        .task(id: TokenStore.shared.token(for: account.tokenKey)) { await feed.run() }
    }
}

// MARK: - Analytics

/// What the DataFast tile counts in the bar.
private enum BusinessDataFastMode: String {
    case now, week
    static let key = "tiles.datafast.mode"
}

private struct BusinessDataFastTile: View {
    @Environment(\.tileContext) private var context
    @AppStorage(BusinessDataFastMode.key) private var storedMode = BusinessDataFastMode.now.rawValue

    /// The library always previews the seven-day total, as the video does.
    private var mode: BusinessDataFastMode {
        context == .library ? .week : BusinessDataFastMode(rawValue: storedMode) ?? .now
    }

    var body: some View {
        Group {
            switch mode {
            case .now:
                BusinessServiceShell(account: .datafast, width: 102, phase: BusinessFeeds.dataFastNow.phase(in: context)) { visitors in
                    BusinessReadout(
                        value: visitors.map(BusinessFormat.count) ?? "7",
                        caption: "visitors now",
                        dot: BusinessPalette.live
                    )
                }
                .task(id: TokenStore.shared.token(for: BusinessAccount.datafast.tokenKey)) {
                    await BusinessFeeds.dataFastNow.run()
                }
            case .week:
                BusinessServiceShell(account: .datafast, width: 131, phase: BusinessFeeds.dataFastWeek.phase(in: context)) { traffic in
                    BusinessReadout(
                        value: traffic.map { BusinessFormat.count($0.visitors) } ?? "1 284",
                        caption: "visitors · last 7d"
                    )
                }
                .task(id: TokenStore.shared.token(for: BusinessAccount.datafast.tokenKey)) {
                    await BusinessFeeds.dataFastWeek.run()
                }
            }
        }
    }
}

private struct BusinessDataFastModePicker: View {
    @AppStorage(BusinessDataFastMode.key) private var mode = BusinessDataFastMode.now.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Show")
                .font(.tileText(10, weight: .semibold))
                .foregroundStyle(TilePalette.ink.opacity(0.6))
            TileChoiceChips(
                options: [
                    (label: "Visitors now", value: BusinessDataFastMode.now.rawValue),
                    (label: "Last 7 days", value: BusinessDataFastMode.week.rawValue),
                ],
                selection: $mode
            )
        }
    }
}

private struct BusinessDataFastChartTile: View {
    @Environment(\.tileContext) private var context

    private static let sample: [Double] = (0..<64).map { index in
        let x = Double(index)
        return x / 63 + 0.055 * sin(x * 1.1) + 0.03 * sin(x * 0.37)
    }

    var body: some View {
        let feed = BusinessFeeds.dataFastWeek
        let phase = feed.phase(in: context)
        DockTile(width: 210, inset: 6) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    readout(phase)
                    Spacer(minLength: 0)
                }
                .padding(.top, 5)
                .frame(maxWidth: .infinity, alignment: .leading)

                BusinessBadge(account: .datafast)
                    .padding(.top, 7)
                    .padding(.trailing, 1)

                VStack {
                    Spacer(minLength: 0)
                    let values = series(phase)
                    if values.count > 1 {
                        BusinessLineChart(
                            values: values,
                            stroke: LinearGradient(
                                colors: [Color(red: 0.97, green: 0.58, blue: 0.30), Color(red: 0.93, green: 0.33, blue: 0.24)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            fill: Color(red: 0.93, green: 0.40, blue: 0.26),
                            lineWidth: 1.7
                        )
                        .frame(height: 15)
                        .padding(.bottom, 5)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .modifier(BusinessConnectTap(phase: phase))
        .task(id: TokenStore.shared.token(for: BusinessAccount.datafast.tokenKey)) { await feed.run() }
    }

    private func readout(_ phase: BusinessPhase<BusinessTraffic>) -> BusinessReadout {
        switch phase {
        case .live(let traffic):
            BusinessReadout(value: BusinessFormat.count(traffic.visitors), caption: "visitors · last 7d")
        case .sample:
            BusinessReadout(value: "1 284", caption: "visitors · last 7d")
        case .connect:
            BusinessReadout(value: "DataFast", caption: "Connect", captionTint: TilePalette.focus, valueSize: 15)
        case .loading:
            BusinessReadout(value: "—", caption: "visitors · last 7d")
        case .failed:
            BusinessReadout(value: "—", caption: "Check token", captionTint: TilePalette.destructive)
        }
    }

    private func series(_ phase: BusinessPhase<BusinessTraffic>) -> [Double] {
        switch phase {
        case .live(let traffic): traffic.series
        case .sample: Self.sample
        default: []
        }
    }
}

private struct BusinessClaudeUsageTile: View {
    @Environment(\.tileContext) private var context

    var body: some View {
        let feed = BusinessFeeds.claude
        BusinessServiceShell(account: .anthropic, width: 175, phase: feed.phase(in: context)) { usage in
            guard let usage else {
                return BusinessReadout(value: "1.2M", caption: "tokens · last 7d", footnote: "42,80 US$ · in 892K")
            }
            let input = "in \(BusinessFormat.compact(usage.inputTokens))"
            return BusinessReadout(
                value: BusinessFormat.compact(usage.tokens),
                caption: "tokens · last 7d",
                footnote: usage.cost.map { "\(BusinessFormat.cost($0, fractionDigits: 2)) · \(input)" } ?? input
            )
        }
        .task(id: TokenStore.shared.token(for: BusinessAccount.anthropic.tokenKey)) { await feed.run() }
    }
}

private struct BusinessCursorUsageTile: View {
    @Environment(\.tileContext) private var context

    var body: some View {
        let feed = BusinessFeeds.cursor
        BusinessServiceShell(account: .cursor, width: 174, phase: feed.phase(in: context)) { usage in
            guard let usage else {
                return BusinessReadout(value: "128 US$", caption: "spent · last 7d", footnote: "1.2K req · 9.2M tok")
            }
            return BusinessReadout(
                value: BusinessFormat.cost(usage.spent, fractionDigits: 0),
                caption: "spent · last 7d",
                footnote: "\(BusinessFormat.compact(usage.requests)) req · \(BusinessFormat.compact(usage.tokens)) tok"
            )
        }
        .task(id: TokenStore.shared.token(for: BusinessAccount.cursor.tokenKey)) { await feed.run() }
    }
}

// MARK: - Stock tiles

private struct BusinessStockTile: View {
    @AppStorage(BusinessStockKeys.stock) private var stored = "AAPL"
    private var symbol: String { BusinessStockKeys.symbols(stored, defaults: ["AAPL"])[0] }

    var body: some View {
        let quote = BusinessStockQuotes.shared.quotes[symbol]
        DockTile(width: 157, inset: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(symbol)
                        .font(.tileText(9, weight: .bold))
                        .foregroundStyle(TilePalette.ink)
                    Text(quote?.name ?? "")
                        .font(.tileCaption(8))
                        .foregroundStyle(TilePalette.caption)
                        .lineLimit(1)
                }
                Text(quote.map { BusinessFormat.price($0.price) } ?? "—")
                    .font(.tileValue(21))
                    .foregroundStyle(TilePalette.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(quote.map { "\(BusinessFormat.signed($0.change)) (\(BusinessFormat.signed($0.percent))%)" } ?? " ")
                    .font(.tileCaption(9))
                    .foregroundStyle(BusinessPalette.trend(quote?.change ?? 0))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: symbol) { await BusinessStockQuotes.shared.run(symbols: [symbol]) }
    }
}

private struct BusinessStockChartTile: View {
    @AppStorage(BusinessStockKeys.chart) private var stored = "AAPL"
    private var symbol: String { BusinessStockKeys.symbols(stored, defaults: ["AAPL"])[0] }

    var body: some View {
        let quote = BusinessStockQuotes.shared.quotes[symbol]
        let tint = BusinessPalette.trend(quote?.change ?? 0)
        DockTile(width: 135, inset: 12) {
            ZStack(alignment: .top) {
                HStack(alignment: .top, spacing: 4) {
                    Text(symbol)
                        .font(.tileText(9, weight: .bold))
                        .foregroundStyle(TilePalette.ink)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(quote.map { BusinessFormat.price($0.price) } ?? "—")
                            .font(.tileText(10.5, weight: .semibold))
                            .foregroundStyle(TilePalette.ink)
                            .monospacedDigit()
                        Text(quote.map { "\(BusinessFormat.signed($0.percent))%" } ?? " ")
                            .font(.tileCaption(8.5, weight: .semibold))
                            .foregroundStyle(tint)
                            .monospacedDigit()
                    }
                }
                .padding(.top, 6)

                VStack {
                    Spacer(minLength: 0)
                    if let closes = quote?.closes, closes.count > 1 {
                        BusinessLineChart(values: closes, stroke: tint, fill: tint, lineWidth: 1.6)
                            .frame(height: 21)
                            .padding(.bottom, 5)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .task(id: symbol) { await BusinessStockQuotes.shared.run(symbols: [symbol]) }
    }
}

private struct BusinessStockWatchlistTile: View {
    @AppStorage(BusinessStockKeys.watchlist) private var stored = BusinessStockKeys.watchlistDefaults.joined(separator: ",")
    private var symbols: [String] {
        BusinessStockKeys.symbols(stored, defaults: BusinessStockKeys.watchlistDefaults)
    }

    var body: some View {
        let quotes = BusinessStockQuotes.shared.quotes
        DockTile(width: 204, inset: 12) {
            VStack(spacing: 0) {
                ForEach(symbols, id: \.self) { symbol in
                    let quote = quotes[symbol]
                    HStack(spacing: 0) {
                        Text(symbol)
                            .font(.tileText(9, weight: .bold))
                            .foregroundStyle(TilePalette.ink)
                            .lineLimit(1)
                            .frame(width: 44, alignment: .leading)
                        Text(quote.map { BusinessFormat.price($0.price) } ?? "—")
                            .font(.tileText(9.5, weight: .semibold))
                            .foregroundStyle(TilePalette.ink.opacity(0.9))
                            .monospacedDigit()
                        Spacer(minLength: 4)
                        Text(quote.map { "\(BusinessFormat.signed($0.percent))%" } ?? "")
                            .font(.tileCaption(8.5, weight: .semibold))
                            .foregroundStyle(BusinessPalette.trend(quote?.change ?? 0))
                            .monospacedDigit()
                    }
                    .frame(height: 14.2)
                }
            }
        }
        .task(id: symbols) { await BusinessStockQuotes.shared.run(symbols: symbols) }
    }
}

// MARK: - Charts

/// A smoothed line with a soft fill down to the bottom edge.
private struct BusinessLineChart<Stroke: ShapeStyle>: View {
    var values: [Double]
    var stroke: Stroke
    var fill: Color
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            BusinessAreaShape(values: values)
                .fill(LinearGradient(colors: [fill.opacity(0.28), fill.opacity(0)], startPoint: .top, endPoint: .bottom))
            Sparkline(values: values)
                .stroke(stroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct BusinessAreaShape: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Sparkline(values: values).path(in: rect)
        guard values.count > 1 else { return path }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Settings

/// The account section of a service tile's settings: token entry, status and
/// a link to where the token is made.
private struct BusinessAccountSettings: View {
    let account: BusinessAccount
    var extra: AnyView?

    @State private var draft = ""
    @State private var revealed = false

    private var stored: String? { TokenStore.shared.token(for: account.tokenKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let extra {
                extra
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    BusinessBrandMark(account: account, diameter: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.title)
                            .font(.tileText(11.5, weight: .semibold))
                            .foregroundStyle(TilePalette.ink.opacity(0.92))
                        Text(stored == nil ? "Not connected" : "Connected")
                            .font(.tileText(9, weight: .medium))
                            .foregroundStyle(stored == nil ? TilePalette.ink.opacity(0.4) : BusinessPalette.up)
                    }
                    Spacer(minLength: 0)
                    if let url = URL(string: account.docs) {
                        Link(destination: url) {
                            HStack(spacing: 2) {
                                Text("Get a key")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.tileText(9, weight: .semibold))
                            .foregroundStyle(TilePalette.focus)
                        }
                    }
                }

                HStack(spacing: 6) {
                    Group {
                        if revealed {
                            TextField(account.placeholder, text: $draft)
                        } else {
                            SecureField(account.placeholder, text: $draft)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(TilePalette.ink.opacity(0.9))
                    .onSubmit(save)

                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(TilePalette.ink.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .help(revealed ? "Hide" : "Show")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: min(7, TileMetrics.corner), style: .continuous)
                        .fill(TilePalette.ink.opacity(0.07))
                }

                Text(account.hint)
                    .font(.tileText(9, weight: .medium))
                    .foregroundStyle(TilePalette.ink.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)

                if let error = TokenStore.shared.errors[account.tokenKey] {
                    Text("Couldn't update the keychain: \(error)")
                        .font(.tileText(9, weight: .medium))
                        .foregroundStyle(TilePalette.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if stored != nil {
                        Button("Disconnect") {
                            draft = ""
                            TokenStore.shared.set("", for: account.tokenKey)
                        }
                        .buttonStyle(BusinessSettingsButtonStyle(tint: TilePalette.destructive, prominent: false))
                    }
                    Spacer(minLength: 0)
                    Button(stored == nil ? "Connect" : "Save", action: save)
                        .buttonStyle(BusinessSettingsButtonStyle(tint: TilePalette.focus, prominent: true))
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft == stored)
                }
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: min(10, TileMetrics.corner), style: .continuous)
                    .fill(TilePalette.ink.opacity(0.045))
            }
        }
        .frame(width: 252)
        .onAppear { draft = stored ?? "" }
        // The keychain is read in the background at launch; fill the field
        // when the token arrives after the popover opened.
        .onChange(of: stored) { _, new in
            if draft.isEmpty, let new { draft = new }
        }
    }

    private func save() {
        TokenStore.shared.set(draft, for: account.tokenKey)
    }
}

private struct BusinessSettingsButtonStyle: ButtonStyle {
    var tint: Color
    var prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.tileText(10, weight: .semibold))
            .foregroundStyle(prominent ? TilePalette.onFocus : tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(prominent ? tint : tint.opacity(0.14))
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

/// Picks the symbol of a stock tile, or the three symbols of the watchlist.
private struct BusinessSymbolSettings: View {
    let key: String
    let defaults: [String]

    @State private var drafts: [String] = []

    private static let suggestions = ["AAPL", "MSFT", "NVDA", "GOOGL", "AMZN", "META", "TSLA"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(defaults.count > 1 ? "Symbols" : "Symbol")
                .font(.tileText(10, weight: .semibold))
                .foregroundStyle(TilePalette.ink.opacity(0.6))
            ForEach(drafts.indices, id: \.self) { index in
                TextField(defaults[index], text: binding(index))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(TilePalette.ink.opacity(0.92))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: min(7, TileMetrics.corner), style: .continuous)
                            .fill(TilePalette.ink.opacity(0.07))
                    }
                    .onSubmit(save)
            }
            if defaults.count == 1 {
                TileChoiceChips(
                    options: Self.suggestions.prefix(5).map { (label: $0, value: $0) },
                    selection: Binding(
                        get: { drafts.first ?? "" },
                        set: { drafts = [$0]; save() }
                    )
                )
            }
            Text("Any Yahoo Finance ticker — BRK-B, ^GSPC, BTC-USD.")
                .font(.tileText(9, weight: .medium))
                .foregroundStyle(TilePalette.ink.opacity(0.4))
        }
        .frame(width: 252, alignment: .leading)
        .onAppear {
            drafts = BusinessStockKeys.symbols(UserDefaults.standard.string(forKey: key), defaults: defaults)
        }
        .onDisappear(perform: save)
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(
            get: { drafts.indices.contains(index) ? drafts[index] : "" },
            set: { value in
                guard drafts.indices.contains(index) else { return }
                drafts[index] = value.uppercased().filter { !$0.isWhitespace && $0 != "," }
            }
        )
    }

    private func save() {
        let cleaned = drafts.enumerated().map { index, value in value.isEmpty ? defaults[index] : value }
        guard !cleaned.isEmpty else { return }
        UserDefaults.standard.set(cleaned.joined(separator: ","), forKey: key)
    }
}

// MARK: - Brand marks

/// The round provider marks drawn in the video: X, TikTok and YouTube at
/// full size, the others as corner badges.
private struct BusinessBrandMark: View {
    let account: BusinessAccount
    let diameter: CGFloat

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let d = size.width
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * d, y: y * d) }

            switch account {
            case .x:
                context.fill(Circle().path(in: rect), with: .color(.black))
                // The thick stroke is drawn as an outline, the thin one in two
                // pieces either side of it.
                let glyph = { (x: CGFloat, y: CGFloat) in point(0.26 + x * 0.48, 0.25 + y * 0.50) }
                var band = Path()
                band.move(to: glyph(0, 0))
                band.addLine(to: glyph(0.30, 0))
                band.addLine(to: glyph(1, 1))
                band.addLine(to: glyph(0.70, 1))
                band.closeSubpath()
                context.stroke(band, with: .color(.white), lineWidth: max(0.7, d * 0.028))
                var thin = Path()
                thin.move(to: glyph(0.92, 0))
                thin.addLine(to: glyph(0.92 - 0.84 * 0.40, 0.40))
                thin.move(to: glyph(0.92 - 0.84 * 0.60, 0.60))
                thin.addLine(to: glyph(0.08, 1))
                context.stroke(thin, with: .color(.white), style: StrokeStyle(lineWidth: max(0.9, d * 0.045), lineCap: .butt))

            case .tiktok:
                context.fill(Circle().path(in: rect), with: .color(.white))
                let note = Self.tiktokNote(d: d)
                let style = StrokeStyle(lineWidth: d * 0.10, lineCap: .round, lineJoin: .round)
                context.stroke(note.offsetBy(dx: -d * 0.022, dy: -d * 0.018), with: .color(Color(red: 0.15, green: 0.95, blue: 0.94)), style: style)
                context.stroke(note.offsetBy(dx: d * 0.022, dy: d * 0.018), with: .color(Color(red: 0.99, green: 0.17, blue: 0.33)), style: style)
                context.stroke(note, with: .color(.black), style: style)

            case .youtube:
                context.fill(Circle().path(in: rect), with: .color(Color(red: 0.94, green: 0.08, blue: 0.14)))
                let plate = CGRect(x: d * 0.20, y: d * 0.30, width: d * 0.60, height: d * 0.40)
                context.fill(RoundedRectangle(cornerRadius: d * 0.11, style: .continuous).path(in: plate), with: .color(.white))
                var play = Path()
                play.move(to: point(0.44, 0.40))
                play.addLine(to: point(0.60, 0.50))
                play.addLine(to: point(0.44, 0.60))
                play.closeSubpath()
                context.fill(play, with: .color(Color(red: 0.94, green: 0.08, blue: 0.14)))

            case .polar:
                context.fill(Circle().path(in: rect), with: .color(.black))
                context.stroke(Circle().path(in: rect.insetBy(dx: d * 0.04, dy: d * 0.04)), with: .color(.white.opacity(0.35)), lineWidth: max(0.5, d * 0.05))
                let line = max(0.5, d * 0.035)
                for width in [0.12, 0.30, 0.50] {
                    let meridian = CGRect(x: d * (0.5 - width / 2), y: d * 0.21, width: d * width, height: d * 0.58)
                    context.stroke(Ellipse().path(in: meridian), with: .color(.white.opacity(0.95)), lineWidth: line)
                }

            case .stripe:
                context.fill(Circle().path(in: rect), with: .color(Color(red: 0.36, green: 0.29, blue: 1.0)))
                var flag = Path()
                flag.move(to: point(0.29, 0.36))
                flag.addQuadCurve(to: point(0.72, 0.31), control: point(0.50, 0.30))
                flag.addLine(to: point(0.71, 0.62))
                flag.addQuadCurve(to: point(0.30, 0.68), control: point(0.50, 0.61))
                flag.closeSubpath()
                context.fill(flag, with: .color(.white))

            case .datafast:
                context.fill(Circle().path(in: rect), with: .color(Color(red: 0.97, green: 0.95, blue: 0.93)))
                let bars: [(x: CGFloat, top: CGFloat, color: Color)] = [
                    (0.30, 0.31, Color(red: 0.95, green: 0.72, blue: 0.64)),
                    (0.45, 0.21, Color(red: 0.90, green: 0.32, blue: 0.20)),
                    (0.60, 0.42, Color(red: 0.95, green: 0.76, blue: 0.69)),
                ]
                for bar in bars {
                    let frame = CGRect(x: d * bar.x, y: d * bar.top, width: d * 0.11, height: d * (0.76 - bar.top))
                    context.fill(RoundedRectangle(cornerRadius: d * 0.025).path(in: frame), with: .color(bar.color))
                }

            case .anthropic:
                context.fill(Circle().path(in: rect), with: .color(Color(red: 0.85, green: 0.47, blue: 0.34)))
                var rays = Path()
                for index in 0..<12 {
                    let angle = Double(index) / 12 * 2 * .pi
                    let inner = index.isMultiple(of: 2) ? 0.07 : 0.10
                    rays.move(to: point(0.5 + inner * cos(angle), 0.5 + inner * sin(angle)))
                    rays.addLine(to: point(0.5 + 0.30 * cos(angle), 0.5 + 0.30 * sin(angle)))
                }
                context.stroke(rays, with: .color(.white), style: StrokeStyle(lineWidth: max(0.6, d * 0.055), lineCap: .round))

            case .cursor:
                context.fill(Circle().path(in: rect), with: .color(Color(white: 0.12)))
                context.stroke(Circle().path(in: rect.insetBy(dx: d * 0.04, dy: d * 0.04)), with: .color(.white.opacity(0.4)), lineWidth: max(0.5, d * 0.05))
                // An isometric cube: light top, mid left face, dark right face.
                let top = point(0.5, 0.24), upperLeft = point(0.27, 0.37), upperRight = point(0.73, 0.37)
                let center = point(0.5, 0.50), lowerLeft = point(0.27, 0.63), lowerRight = point(0.73, 0.63)
                let bottom = point(0.5, 0.76)
                func face(_ points: [CGPoint]) -> Path {
                    var path = Path()
                    path.addLines(points)
                    path.closeSubpath()
                    return path
                }
                context.fill(face([top, upperRight, center, upperLeft]), with: .color(Color(white: 0.92)))
                context.fill(face([upperLeft, center, bottom, lowerLeft]), with: .color(Color(white: 0.62)))
                context.fill(face([center, upperRight, lowerRight, bottom]), with: .color(Color(white: 0.38)))
            }
        }
        .frame(width: diameter, height: diameter)
    }

    /// The TikTok note: a ring, its stem and the flag curling right.
    private nonisolated static func tiktokNote(d: CGFloat) -> Path {
        var path = Path()
        let stemX = d * 0.56
        let radius = d * 0.125
        path.addEllipse(in: CGRect(x: stemX - radius * 2, y: d * 0.62 - radius, width: radius * 2, height: radius * 2))
        path.move(to: CGPoint(x: stemX, y: d * 0.62))
        path.addLine(to: CGPoint(x: stemX, y: d * 0.22))
        path.addQuadCurve(to: CGPoint(x: d * 0.76, y: d * 0.41), control: CGPoint(x: stemX + d * 0.03, y: d * 0.38))
        return path
    }
}

/// The glossy blue dot the bar shows next to a provider badge.
private struct BusinessSphere: View {
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.72, green: 0.87, blue: 1.0),
                        Color(red: 0.24, green: 0.56, blue: 1.0),
                        Color(red: 0.04, green: 0.33, blue: 0.95),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .top) {
                Ellipse()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 10, height: 4.5)
                    .padding(.top, 1.5)
            }
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
            }
    }
}
