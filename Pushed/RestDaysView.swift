import SwiftUI

/// The main screen's days off: saving yesterday while that's still possible,
/// taking today off, and the way in to choosing rest days.
struct DaysOffSection: View {
    let history: StreakHistory
    let protection: StreakProtection
    /// Saves the change and repaints the widgets and reminders.
    let apply: (StreakProtection) -> Void

    var body: some View {
        Section {
            if history.canSaveStreak {
                rescue
            }
            today
            if let kind = history.claim(daysAgo: 1) {
                claimed(kind, daysAgo: 1)
            }
            NavigationLink {
                RestDaysView(protection: protection, apply: apply)
            } label: {
                LabeledContent("Rest days", value: restDaySummary)
            }
        } header: {
            Text("Days off")
        } footer: {
            Text(footer)
        }
    }

    // MARK: - Rows

    private var rescue: some View {
        let streak = history.streakBeforeBreak
        return Group {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your \(streak)-day streak can still be saved")
                    .font(.headline)
                Text("Yesterday's square is empty. Cover it before midnight and the streak carries on.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            if history.canClaim(.rest, daysAgo: 1) {
                Button("Use a rest day for yesterday") { claim(.rest, daysAgo: 1) }
            }
            if history.canClaim(.freeze, daysAgo: 1) {
                Button("Use this month's freeze for yesterday") { claim(.freeze, daysAgo: 1) }
            }
        }
    }

    @ViewBuilder
    private var today: some View {
        switch history.today {
        case .pushed:
            EmptyView()
        case .off(let kind):
            if history.claim(daysAgo: 0) != nil {
                claimed(kind, daysAgo: 0)
            } else {
                Label("Today is a rest day. Nothing is owed.", systemImage: "moon.zzz")
                    .foregroundStyle(.secondary)
            }
        case .pending:
            if history.canClaim(.rest, daysAgo: 0) {
                Button("Take today as a rest day") { claim(.rest, daysAgo: 0) }
            }
            if history.canClaim(.freeze, daysAgo: 0) {
                Button("Use this month's freeze today") { claim(.freeze, daysAgo: 0) }
            }
        }
    }

    /// A day taken by hand, which can be given back while it's still today
    /// or yesterday.
    private func claimed(_ kind: DayOff, daysAgo: Int) -> some View {
        HStack {
            Label(
                "\(daysAgo == 0 ? "Today is" : "Yesterday was") \(kind == .rest ? "a rest day" : "frozen")",
                systemImage: kind == .rest ? "moon.zzz" : "snowflake"
            )
            Spacer()
            Button("Undo") {
                guard let date = history.date(daysAgo: daysAgo) else { return }
                var updated = protection
                updated.removeClaim(on: date)
                apply(updated)
            }
            .buttonStyle(.borderless)
        }
    }

    private func claim(_ kind: DayOff, daysAgo: Int) {
        guard let date = history.date(daysAgo: daysAgo) else { return }
        var updated = protection
        updated.claim(kind, on: date)
        apply(updated)
    }

    // MARK: - Words

    private var restDaySummary: String {
        let chosen = protection.chosenWeekdays
        guard !chosen.isEmpty else { return "Off" }
        return Weekday.shortNames(chosen)
    }

    private var footer: String {
        let allowance = min(protection.weekdays(on: Date()).count, StreakProtection.maxRestDays)
        var parts: [String] = []

        if allowance == 0 {
            parts.append("Choose up to two rest days a week and the streak steps over them.")
        } else {
            let left = history.restDaysLeftThisWeek
            parts.append("\(left) of \(allowance) rest day\(allowance == 1 ? "" : "s") left this week.")
        }

        if protection.freezeEnabled {
            if let used = history.freezeUsedThisMonth {
                parts.append("This month's freeze went on \(used.formatted(.dateTime.month(.abbreviated).day())).")
            } else {
                parts.append("This month's freeze is unused.")
            }
        }
        return parts.joined(separator: " ")
    }
}

/// Choosing the weekly rest days, and whether the monthly freeze is on.
struct RestDaysView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var protection: StreakProtection
    private let apply: (StreakProtection) -> Void

    init(protection: StreakProtection, apply: @escaping (StreakProtection) -> Void) {
        _protection = State(initialValue: protection)
        self.apply = apply
    }

    private var chosen: Set<Int> { protection.chosenWeekdays }

    var body: some View {
        Form {
            Section {
                ForEach(Weekday.all, id: \.self) { weekday in
                    let isOn = chosen.contains(weekday)
                    // With two chosen, one has to come off before another goes on.
                    let isLocked = !isOn && chosen.count >= StreakProtection.maxRestDays
                    Button {
                        toggle(weekday)
                    } label: {
                        HStack {
                            Text(Weekday.name(weekday))
                                // Inside a button, .primary means the tint.
                                .foregroundStyle(isLocked ? Color.secondary : Color.primary)
                            Spacer()
                            if isOn {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .disabled(isLocked)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            } header: {
                Text("Rest days")
            } footer: {
                Text(scheduleNote)
            }

            Section {
                legend(StreakDay(level: 2), "Pushed. Counts toward the streak.")
                legend(StreakDay(level: 0, off: .rest), "Day off. The streak carries on, and the day isn't counted.")
                legend(StreakDay(level: 0), "Missed. The streak ends here.")
            } header: {
                Text("On the graph")
            } footer: {
                Text("A rest day only steps in when the day is empty. Push on one and it's an ordinary green square that counts like any other. Your squares always match GitHub's: a day off is marked, never filled in.")
            }

            Section {
                Text("Need a different day off this week? Take it from the main screen, on the day itself or the day after. It uses one of the week's rest days, so a later one that week isn't covered.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Moving a rest day")
            }

            Section {
                Toggle("Monthly freeze", isOn: Binding(
                    get: { protection.freezeEnabled },
                    set: { isOn in
                        protection.freezeEnabled = isOn
                        apply(protection)
                    }
                ))
            } header: {
                Text("Freeze")
            } footer: {
                Text("One day a month for a day off you didn't plan, on top of your rest days. Use it from the main screen on the day or the day after.")
            }
        }
        .navigationTitle("Rest Days")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ weekday: Int) {
        var weekdays = chosen
        if weekdays.contains(weekday) {
            weekdays.remove(weekday)
        } else {
            weekdays.insert(weekday)
        }
        protection.setWeekdays(weekdays, asOf: Date())
        apply(protection)
    }

    /// Says when a change takes effect, since swapping rest days waits for
    /// the next week.
    private var scheduleNote: String {
        let limit = "Up to two a week, counted Sunday to Saturday."
        guard let start = protection.pendingStart(asOf: Date()) else {
            return chosen.isEmpty ? "\(limit) With none chosen, every empty day ends the streak." : limit
        }
        let current = protection.weekdays(on: Date())
        let startText = start.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return "\(limit) This change starts \(startText). Until then this week stays on \(Weekday.shortNames(current))."
    }

    private func legend(_ day: StreakDay, _ text: String) -> some View {
        HStack(spacing: 12) {
            DayCell(day: day, theme: WidgetStyle.classic.theme(for: colorScheme))
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
        }
    }
}

/// Calendar weekdays, 1 for Sunday through 7 for Saturday.
enum Weekday {
    static let all = Array(1...7)

    /// A calendar made from an identifier alone has no locale, and hands
    /// back short names for both lists.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        return calendar
    }()

    static func name(_ weekday: Int) -> String {
        calendar.weekdaySymbols[weekday - 1]
    }

    /// "Sat, Sun": in week order, except that a Sunday paired with a Saturday
    /// goes last, the way a weekend is said.
    static func shortNames(_ weekdays: Set<Int>) -> String {
        let symbols = calendar.shortWeekdaySymbols
        var ordered = weekdays.sorted()
        if ordered == [1, 7] { ordered = [7, 1] }
        return ordered.map { symbols[$0 - 1] }.joined(separator: ", ")
    }
}
