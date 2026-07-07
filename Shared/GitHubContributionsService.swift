import Foundation

struct ContributionDay: Decodable, Identifiable {
    let date: String
    let contributionCount: Int
    var id: String { date }
}

struct ContributionCalendar {
    let totalContributions: Int
    let days: [ContributionDay]

    var committedToday: Bool {
        guard let today = days.last(where: { $0.date == ContributionCalendar.todayString }) else {
            return false
        }
        return today.contributionCount > 0
    }

    var currentStreak: Int {
        let calendar = Calendar(identifier: .gregorian)
        var streak = 0
        var cursor = Date()
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
