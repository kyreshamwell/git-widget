import XCTest

final class PushedLogicTests: XCTestCase {
    private let formatter = ContributionCalendar.dateFormatter
    private let cal = Calendar(identifier: .gregorian)

    /// Builds a calendar of consecutive days ending on `endDate`, where
    /// `activity` maps "yyyy-MM-dd" strings to (count, levelString).
    private func makeCalendar(
        endingOn endDate: String,
        dayCount: Int,
        activity: [String: (Int, String)]
    ) -> ContributionCalendar {
        let end = formatter.date(from: endDate)!
        var days: [ContributionDay] = []
        for offset in stride(from: -(dayCount - 1), through: 0, by: 1) {
            let d = cal.date(byAdding: .day, value: offset, to: end)!
            let ds = formatter.string(from: d)
            let (count, level) = activity[ds] ?? (0, "NONE")
            days.append(ContributionDay(date: ds, contributionCount: count, contributionLevel: level))
        }
        return ContributionCalendar(totalContributions: activity.values.reduce(0) { $0 + $1.0 }, days: days)
    }

    private func date(_ s: String) -> Date { formatter.date(from: s)! }

    // MARK: - Parsing (guards against the QUARTILE bug)

    func testParseMapsQuartileLevels() throws {
        let json = """
        {"data":{"user":{"contributionsCollection":{"contributionCalendar":{
          "totalContributions": 12,
          "weeks": [
            {"contributionDays": [
              {"date":"2026-07-05","contributionCount":0,"contributionLevel":"NONE"},
              {"date":"2026-07-06","contributionCount":1,"contributionLevel":"FIRST_QUARTILE"},
              {"date":"2026-07-07","contributionCount":11,"contributionLevel":"FOURTH_QUARTILE"}
            ]}
          ]
        }}}}}
        """.data(using: .utf8)!

        let calendar = try GitHubContributionsService.parse(json)
        XCTAssertEqual(calendar.totalContributions, 12)
        XCTAssertEqual(calendar.days.map(\.level), [0, 1, 4])
    }

    func testParseThrowsOnMalformedResponse() {
        let bad = #"{"nonsense":true}"#.data(using: .utf8)!
        XCTAssertThrowsError(try GitHubContributionsService.parse(bad))
    }

    // MARK: - Naming the failure
    //
    // A wrong username, a throttled hour and a dead network all used to arrive
    // as one "check username/token", which is unactionable for the two of them
    // that aren't the user's fault.

    func testMistypedUsernameIsNamedAsSuchNotAsABadToken() {
        // GraphQL answers 200 with an errors array — the token is fine.
        let json = #"""
        {"data":{"user":null},"errors":[{"type":"NOT_FOUND","path":["user"],
         "message":"Could not resolve to a User with the login of 'kyre-typo'."}]}
        """#.data(using: .utf8)!

        XCTAssertThrowsError(try GitHubContributionsService.parse(json)) { error in
            XCTAssertEqual(error as? GitHubServiceError, .userNotFound)
        }
    }

    func testNullUserWithoutAnErrorArrayIsStillAMissingUser() {
        let json = #"{"data":{"user":null}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try GitHubContributionsService.parse(json)) { error in
            XCTAssertEqual(error as? GitHubServiceError, .userNotFound)
        }
    }

    func testOtherGraphQLErrorsCarryGitHubsOwnWording() {
        let json = #"""
        {"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded."}]}
        """#.data(using: .utf8)!

        XCTAssertThrowsError(try GitHubContributionsService.parse(json)) { error in
            XCTAssertEqual(error as? GitHubServiceError, .apiError("API rate limit exceeded."))
        }
    }

    // MARK: - 403 disambiguation
    //
    // GitHub returns 403 both for a revoked token and for either rate limit.
    // Collapsing them meant a throttled background refresh told the user their
    // token had died and muted every commit nudge until they "reconnected".

    private func response(status: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!,
            statusCode: status, httpVersion: nil, headerFields: headers
        )!
    }

    func testExhaustedPrimaryRateLimitIsNotReadAsADeadToken() {
        let http = response(status: 403, headers: ["x-ratelimit-remaining": "0"])
        XCTAssertTrue(GitHubContributionsService.isRateLimited(http))
    }

    func testSecondaryRateLimitIsNotReadAsADeadToken() {
        let http = response(status: 403, headers: ["retry-after": "60"])
        XCTAssertTrue(GitHubContributionsService.isRateLimited(http))
    }

    func testA403WithBudgetLeftIsStillATokenProblem() {
        // No throttling signal at all — this is the genuinely revoked case, and
        // it must keep reaching the user as one.
        let http = response(status: 403, headers: ["x-ratelimit-remaining": "4998"])
        XCTAssertFalse(GitHubContributionsService.isRateLimited(http))
        XCTAssertFalse(GitHubContributionsService.isRateLimited(response(status: 403, headers: [:])))
    }

    func testUnknownLevelStringFallsBackToCounts() {
        // If GitHub renames the enum again, active days must not turn grey.
        let day = ContributionDay(date: "2026-07-07", contributionCount: 5, contributionLevel: "SOMETHING_NEW")
        XCTAssertGreaterThan(day.level, 0)

        let quiet = ContributionDay(date: "2026-07-07", contributionCount: 0, contributionLevel: "SOMETHING_NEW")
        XCTAssertEqual(quiet.level, 0)
    }

    // MARK: - Token expiry header

    func testParsesTheRealTokenExpiryHeaderFormat() throws {
        // Verbatim from GitHub's GraphQL response headers.
        let parsed = try XCTUnwrap(
            GitHubContributionsService.parseTokenExpiry("2026-09-04 15:17:49 UTC"),
            "GitHub's actual header format must parse, or expiry warnings never fire"
        )
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-04T15:17:49Z"))
        XCTAssertEqual(parsed.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
    }

    func testUnparseableExpiryDegradesToNoWarningsRatherThanAWrongDate() {
        XCTAssertNil(GitHubContributionsService.parseTokenExpiry(nil))
        XCTAssertNil(GitHubContributionsService.parseTokenExpiry(""))
        XCTAssertNil(GitHubContributionsService.parseTokenExpiry("   "))
        XCTAssertNil(GitHubContributionsService.parseTokenExpiry("never"))
    }

    // MARK: - Streak math

    func testStreakHoldsWhenTodayHasNoCommitYet() {
        // 3-day streak through yesterday, nothing today — must show 3, not 0.
        let calendar = makeCalendar(endingOn: "2026-07-07", dayCount: 30, activity: [
            "2026-07-04": (2, "FIRST_QUARTILE"),
            "2026-07-05": (1, "FIRST_QUARTILE"),
            "2026-07-06": (3, "SECOND_QUARTILE"),
        ])
        XCTAssertEqual(calendar.currentStreak(asOf: date("2026-07-07")), 3)
        XCTAssertFalse(calendar.hasContribution(on: date("2026-07-07")))
    }

    func testStreakIncludesTodayOncePushed() {
        let calendar = makeCalendar(endingOn: "2026-07-07", dayCount: 30, activity: [
            "2026-07-06": (1, "FIRST_QUARTILE"),
            "2026-07-07": (2, "FIRST_QUARTILE"),
        ])
        XCTAssertEqual(calendar.currentStreak(asOf: date("2026-07-07")), 2)
        XCTAssertTrue(calendar.hasContribution(on: date("2026-07-07")))
    }

    func testStreakResetsAfterMissedDay() {
        // Active two days ago, grey yesterday, nothing today -> streak 0.
        let calendar = makeCalendar(endingOn: "2026-07-07", dayCount: 30, activity: [
            "2026-07-05": (4, "SECOND_QUARTILE"),
        ])
        XCTAssertEqual(calendar.currentStreak(asOf: date("2026-07-07")), 0)
    }

    // MARK: - Snapshot week alignment

    func testSnapshotStartsOnSundayAndEndsToday() {
        // Jul 7 2026 is a Tuesday: expect 3 trailing partial days (Sun/Mon/Tue).
        let calendar = makeCalendar(endingOn: "2026-07-07", dayCount: 370, activity: [
            "2026-07-07": (2, "FIRST_QUARTILE"),
        ])
        let snapshot = ContributionSnapshot.from(calendar)

        XCTAssertEqual(snapshot.recentLevels.count % 7, 3, "current week should be 3 days")
        XCTAssertEqual(snapshot.lastDate, "2026-07-07")
        XCTAssertEqual(snapshot.recentLevels.last, 1, "today's square must be the last entry")

        let firstDate = cal.date(byAdding: .day, value: -(snapshot.recentLevels.count - 1), to: date("2026-07-07"))!
        XCTAssertEqual(cal.component(.weekday, from: firstDate), 1, "grid column 0 must start on a Sunday")
    }

    func testLevelsForWeeksKeepsAlignmentAndToday() {
        let calendar = makeCalendar(endingOn: "2026-07-07", dayCount: 370, activity: [
            "2026-07-07": (2, "FIRST_QUARTILE"),
        ])
        let snapshot = ContributionSnapshot.from(calendar)

        for weeks in [4, 13, 26, 52] {
            let slice = snapshot.levels(forWeeks: weeks)
            XCTAssertEqual(slice.count % 7, 3, "\(weeks)wk slice must keep the 3-day partial week")
            XCTAssertEqual(slice.last, 1, "\(weeks)wk slice must still end on today")
            XCTAssertLessThanOrEqual(slice.count, weeks * 7 + 6)
        }
    }

    func testSnapshotSurvivesEncodeDecodeRoundTrip() throws {
        let calendar = makeCalendar(endingOn: "2026-07-07", dayCount: 100, activity: [
            "2026-07-01": (9, "FOURTH_QUARTILE"),
        ])
        let original = ContributionSnapshot.from(calendar)
        let decoded = try JSONDecoder().decode(ContributionSnapshot.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded.recentLevels, original.recentLevels)
        XCTAssertEqual(decoded.lastDate, original.lastDate)
        XCTAssertEqual(decoded.currentStreak, original.currentStreak)
    }
}
