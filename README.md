# Pushed

An iPhone home-screen widget that shows your current GitHub commit streak, so there's a visible nudge every time you unlock your phone.

## Structure

- `Pushed/`: the container app. Setup (GitHub username and personal access token), then your graph, stats, reminders and widget settings.
- `PushedWidget/`: the WidgetKit extension. Small, medium and large sizes, plus the Edit Widget options (`WidgetOptionsIntent.swift`).
- `Shared/`: code used by both. Keychain storage for the token, the GitHub GraphQL fetch, streak calculation, the snapshot cache that lets the widget render instantly from the last known data, and the widget's views and styles (`StreakWidgetView.swift`, `WidgetStyle.swift`), which live here so the app's style gallery draws the exact same thing.

## Widget styles

Each placed widget has its own **Style** and **Layout**, chosen by long-pressing it and tapping **Edit Widget**, so different looks can sit side by side on one home screen.

- **Styles:** Classic (GitHub's greens, follows light and dark mode), Aurora, Ember, Terminal, Paper, and Custom. Every built-in color, backdrop and cell shape lives in `Shared/WidgetStyle.swift`; adding a style means one new case there plus a line in `WidgetOptionsIntent.swift`.
- **Custom** is designed in the app under **Widget → Custom style**: background (solid or gradient), square color, cell shape, font and glow. It's saved in the shared app group (`Shared/CustomWidgetStyle.swift`) and every widget set to Custom uses it. Text color, empty days and the status dot are derived from the choices using WCAG contrast, so no combination can make the widget unreadable.
- **Layouts:** Graph (the contribution graph with the streak in a footer) and Big streak (the number up front, recent weeks beside it). The widget turns off the system's automatic margins and applies them itself: Big streak uses the standard ones, while Graph trims them so its squares can run closer to the edges.
- On tinted and clear home screens iOS drops the backdrop and recolors everything, so every style falls back to white at stepped opacity (`WidgetTheme.monochrome`) to keep the levels readable.
- The app's **Widget → Styles** screen previews all of them with your own data, and Xcode's canvas has a preview per style in `PushedWidget.swift`.

The streak icon is any single emoji, picked from the emoji keyboard in **Widget → Streak icon**.

Generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml` — don't hand-edit `Pushed.xcodeproj`; edit `project.yml` and re-run `xcodegen generate`.

## First-time setup

1. Open `Pushed.xcodeproj` in Xcode.
2. Xcode → Settings → Accounts — make sure your Apple ID is signed in.
3. The signing team is set in `project.yml` (`DEVELOPMENT_TEAM`) rather than in the Xcode UI — `xcodegen generate` rewrites the pbxproj, so a team picked in the UI gets wiped on the next run. Change it there if you're building under a different account.
4. In Signing & Capabilities, confirm both targets have **App Groups** (`group.com.kyreshamwell.pushed`) and **Keychain Sharing** (`com.kyreshamwell.pushed.shared`) enabled — `project.yml` already declares these as entitlements, Xcode should just need to register them with your team the first time you build.
5. Build & run the `Pushed` scheme on your iPhone (or simulator).
6. In the app, enter your GitHub username and a **classic** personal access token with the `read:user` scope — create one at [github.com/settings/tokens](https://github.com/settings/tokens). Tap **Connect**.
7. Long-press your home screen → **+** → search "Pushed" → add the small or medium widget.

If you want private contributions counted too, enable "Include private contributions on my profile" in your GitHub profile settings — the token scope alone doesn't control that.

## Submitting to the App Store

The code side is handled — `PrivacyInfo.xcprivacy` ships in both the app and the
widget bundle, the App Store icon is opaque, and the app is pinned to portrait.
What's left can't be done from the repo:

- **Give App Review a demo account.** The app is unusable without a GitHub
  username and token, and a reviewer has no way to produce one. Put a working
  username and a `read:user` PAT in App Store Connect → *App Review Information
  → Sign-in required → Notes*. Skipping this is the most likely first-pass
  rejection. Use a throwaway GitHub account with some contribution history, and
  give the token a long expiry so it outlives the review.
- **Host [PRIVACY.md](PRIVACY.md) at a public URL** and paste that into the
  *Privacy Policy URL* field. GitHub Pages on this repo is enough.
- **Answer the App Privacy questionnaire as "Data Not Collected."** Nothing
  leaves the device except the GitHub API call, which is the user's own request
  to a third party — that isn't collection by the developer.
- **Bump `CURRENT_PROJECT_VERSION` in `project.yml`** (not in Xcode) before each
  upload, then re-run `xcodegen generate`.
- If asked about `UIBackgroundModes: fetch`, the honest answer is that the
  background refresh keeps the widget and the reminder schedule current; it is
  the fallback path for users who never add the widget.

## Screenshots

Screenshots belong to an app version in App Store Connect. They can be changed while that version is in Prepare for Submission or after a rejection; once a version is approved, new screenshots go in with the next version.

Debug builds have a demo mode that fills the app and widget with a believable sample year, so every screen can be captured on a simulator without a GitHub account. The fake token stays in memory, and the next normal launch clears the sample data.

```bash
xcrun simctl launch booted com.kyreshamwell.pushed -PushedDemo
```

Use the **iPhone 17 Pro Max** simulator: its screenshots come out at 1320 × 2868, one of the accepted sizes for the required 6.9" iPhone set, and App Store Connect scales them down for smaller iPhones. Press ⌘S in Simulator to save one. Widgets added to the simulator's home screen use the sample data too.

## Notes

- The widget refreshes roughly every 2 hours (iOS budgets background refreshes, so it won't be instant). Opening the app and hitting **Refresh now** force-refreshes immediately.
- Streak counts today as part of the streak once you've committed; if you haven't committed yet today, the streak shown is your count through yesterday so it doesn't drop to 0 before the day's over.
