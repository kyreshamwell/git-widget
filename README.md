# GitStreak

An iPhone home-screen widget that shows your current GitHub commit streak, so there's a visible nudge every time you unlock your phone.

## Structure

- `GitStreak/` — the container app. One screen: enter your GitHub username + a personal access token.
- `GitStreakWidget/` — the WidgetKit extension. Small size shows streak count + "committed today?" dot; medium size adds a mini contribution heatmap.
- `Shared/` — code used by both: Keychain storage for the token, the GitHub GraphQL fetch, streak calculation, and the snapshot cache that lets the widget render instantly from the last known data.

Generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml` — don't hand-edit `GitStreak.xcodeproj`; edit `project.yml` and re-run `xcodegen generate`.

## First-time setup

1. Open `GitStreak.xcodeproj` in Xcode.
2. Xcode → Settings → Accounts — make sure your Apple ID is signed in.
3. Select the `GitStreak` project in the navigator → for both the `GitStreak` and `GitStreakWidgetExtension` targets, set **Team** to your personal team under Signing & Capabilities.
4. Still in Signing & Capabilities, confirm both targets have **App Groups** (`group.com.kyreshamwell.gitstreak`) and **Keychain Sharing** (`com.kyreshamwell.gitstreak.shared`) enabled — `project.yml` already declares these as entitlements, Xcode should just need to register them with your team the first time you build.
5. Build & run the `GitStreak` scheme on your iPhone (or simulator).
6. In the app, enter your GitHub username and a **classic** personal access token with the `read:user` scope — create one at [github.com/settings/tokens](https://github.com/settings/tokens). Tap **Save & Test**.
7. Long-press your home screen → **+** → search "GitStreak" → add the small or medium widget.

If you want private contributions counted too, enable "Include private contributions on my profile" in your GitHub profile settings — the token scope alone doesn't control that.

## Notes

- The widget refreshes roughly every 2 hours (iOS budgets background refreshes, so it won't be instant). Opening the app and hitting **Save & Test** force-refreshes immediately.
- Streak counts today as part of the streak once you've committed; if you haven't committed yet today, the streak shown is your count through yesterday so it doesn't drop to 0 before the day's over.
