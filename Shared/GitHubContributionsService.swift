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

enum GitHubServiceError: Error {
    case missingCredentials
    case requestFailed
    case decodingFailed
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

    static func fetchCalendar(username: String, token: String) async throws -> ContributionCalendar {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "variables": ["userName": username],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubServiceError.requestFailed
        }

        return try parse(data)
    }

    /// Split out from the network call so tests can exercise it directly.
    static func parse(_ data: Data) throws -> ContributionCalendar {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
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
