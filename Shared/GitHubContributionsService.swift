import Foundation

struct ContributionDay: Decodable, Identifiable {
    let date: String
    let contributionCount: Int
    let contributionLevel: String // NONE, FIRST_QUARTILE, SECOND_QUARTILE, THIRD_QUARTILE, FOURTH_QUARTILE
    var id: String { date }

    // 0-4, matching the shade GitHub uses on the profile graph. Falls back to
    // count-based shading if GitHub ever renames the enum, so an unrecognized
    // string can't silently grey out active days.
    var level: Int {
        switch contributionLevel {
        case "NONE": return 0
        case "FIRST_QUARTILE": return 1
        case "SECOND_QUARTILE": return 2
        case "THIRD_QUARTILE": return 3
        case "FOURTH_QUARTILE": return 4
        default: return contributionCount == 0 ? 0 : min(1 + contributionCount / 3, 4)
        }
    }
}

struct ContributionCalendar {
    let totalContributions: Int
    let days: [ContributionDay]

    var committedToday: Bool { hasContribution(on: Date()) }
    var currentStreak: Int { currentStreak(asOf: Date()) }

    // The date-parameterized variants exist so tests can pin "today" instead of
    // depending on the wall clock.
    func hasContribution(on date: Date) -> Bool {
        let key = ContributionCalendar.dateFormatter.string(from: date)
        guard let day = days.last(where: { $0.date == key }) else { return false }
        return day.contributionCount > 0
    }

    func currentStreak(asOf now: Date) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        var streak = 0
        var cursor = now
        let byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0.contributionCount) })
        let formatter = ContributionCalendar.dateFormatter

        // If today has no contribution yet, that's fine — start counting from yesterday
        // so a streak in progress doesn't reset to 0 before the day is over.
        if let count = byDate[formatter.string(from: cursor)], count > 0 {
            streak += 1
        }
        cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!

        while let count = byDate[formatter.string(from: cursor)], count > 0 {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    static var todayString: String { dateFormatter.string(from: Date()) }
}

enum GitHubServiceError: Error, Equatable {
    case missingCredentials
    case requestFailed
    /// The token was rejected — expired or revoked. Distinct from a network
    /// blip because it's the one failure the user has to act on, and the one
    /// that must silence commit nudges (data we can't read can't be nagged about).
    case unauthorized
    /// GitHub is throttling us. Shares the 403 status code with a revoked token,
    /// but means the opposite thing: wait and it fixes itself. Kept separate so
    /// a busy hour can't be reported to the user as a dead token.
    case rateLimited
    /// The token works; the login doesn't exist. Worth its own case because the
    /// fix is a typo correction, not a new token.
    case userNotFound
    /// GraphQL answered 200 with an `errors` array. Carries GitHub's own wording.
    case apiError(String)
    case decodingFailed
}

/// A fetch carries the token's own lifecycle alongside the contribution data —
/// GitHub reports the expiry date on every authenticated response, so the
/// 10/5/1-day warnings cost no extra request.
struct CalendarFetch {
    let calendar: ContributionCalendar
    let tokenExpiry: Date?
}

enum GitHubContributionsService {
    private static let endpoint = URL(string: "https://api.github.com/graphql")!

    private static let query = """
    query($userName: String!) {
      user(login: $userName) {
        contributionsCollection {
          contributionCalendar {
            totalContributions
            weeks {
              contributionDays {
                date
                contributionCount
                contributionLevel
              }
            }
          }
        }
      }
    }
    """

    /// Header GitHub sets on authenticated responses when the token has an
    /// expiry date. Absent for never-expiring tokens.
    static let expiryHeader = "github-authentication-token-expiration"

    static func fetch(username: String, token: String) async throws -> CalendarFetch {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "variables": ["userName": username],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubServiceError.requestFailed
        }
        if http.statusCode == 401 {
            throw GitHubServiceError.unauthorized
        }
        // 403 is overloaded: GitHub returns it for a revoked token *and* for
        // both flavours of rate limit. Reading them as the same thing meant a
        // throttled background refresh told the user their token had died and
        // silenced every commit nudge until they reconnected a working token.
        if http.statusCode == 403 || http.statusCode == 429 {
            throw isRateLimited(http) ? GitHubServiceError.rateLimited : GitHubServiceError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw GitHubServiceError.requestFailed
        }

        return CalendarFetch(
            calendar: try parse(data),
            tokenExpiry: parseTokenExpiry(http.value(forHTTPHeaderField: expiryHeader))
        )
    }

    static func fetchCalendar(username: String, token: String) async throws -> ContributionCalendar {
        try await fetch(username: username, token: token).calendar
    }

    /// GitHub has shipped this header in more than one shape over the years, so
    /// try the known formats rather than trusting one. An unparseable value
    /// degrades to "no expiry known", which just means no early warnings —
    /// never a wrong date.
    static func parseTokenExpiry(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }

        for format in ["yyyy-MM-dd HH:mm:ss ZZZ", "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }

        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        rfc.dateFormat = "EEE, dd MMM yyyy HH:mm:ss ZZZ"
        return rfc.date(from: raw)
    }

    /// Tells a throttled 403 apart from a revoked one. GitHub signals the
    /// primary limit by zeroing `x-ratelimit-remaining` and the secondary
    /// (abuse) limit with `retry-after`; a revoked token carries neither.
    /// Anything ambiguous falls through to "not rate limited", so the only way
    /// to be told your token is dead is for GitHub to give no throttling signal
    /// at all.
    static func isRateLimited(_ http: HTTPURLResponse) -> Bool {
        if http.value(forHTTPHeaderField: "retry-after") != nil { return true }
        if let remaining = http.value(forHTTPHeaderField: "x-ratelimit-remaining"),
           Int(remaining.trimmingCharacters(in: .whitespaces)) == 0 { return true }
        return false
    }

    /// Split out from the network call so tests can exercise it directly.
    static func parse(_ data: Data) throws -> ContributionCalendar {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubServiceError.decodingFailed
        }

        // GraphQL reports failure with HTTP 200 and an `errors` array, so a
        // mistyped username used to surface as the same "check username/token"
        // as a dead network. GitHub already words these well; pass its wording
        // through rather than inventing a vaguer one.
        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            if errors.contains(where: { ($0["type"] as? String) == "NOT_FOUND" }) {
                throw GitHubServiceError.userNotFound
            }
            throw GitHubServiceError.apiError(
                (errors.first?["message"] as? String) ?? "GitHub rejected the request."
            )
        }

        // A null user with no error array means the same thing as NOT_FOUND.
        if let dataDict = json["data"] as? [String: Any], dataDict["user"] is NSNull {
            throw GitHubServiceError.userNotFound
        }

        guard
            let dataDict = json["data"] as? [String: Any],
            let user = dataDict["user"] as? [String: Any],
            let collection = user["contributionsCollection"] as? [String: Any],
            let calendarDict = collection["contributionCalendar"] as? [String: Any],
            let total = calendarDict["totalContributions"] as? Int,
            let weeks = calendarDict["weeks"] as? [[String: Any]]
        else {
            throw GitHubServiceError.decodingFailed
        }

        let allDaysData = weeks.flatMap { week -> [Any] in
            (week["contributionDays"] as? [Any]) ?? []
        }
        let daysJSON = try JSONSerialization.data(withJSONObject: allDaysData)
        let days = try JSONDecoder().decode([ContributionDay].self, from: daysJSON)

        return ContributionCalendar(totalContributions: total, days: days)
    }
}
