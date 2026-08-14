# Pushed

An iPhone home-screen widget that shows your current GitHub commit streak, so there's a visible nudge every time you unlock your phone.

## Structure

- `Pushed/` — the container app. One screen: enter your GitHub username + a personal access token.
- `PushedWidget/` — the WidgetKit extension. Small size shows streak count + "committed today?" dot; medium size adds a mini contribution heatmap.
- `Shared/` — code used by both: Keychain storage for the token, the GitHub GraphQL fetch, streak calculation, and the snapshot cache that lets the widget render instantly from the last known data.

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

## Notes

- The widget refreshes roughly every 2 hours (iOS budgets background refreshes, so it won't be instant). Opening the app and hitting **Refresh now** force-refreshes immediately.
- Streak counts today as part of the streak once you've committed; if you haven't committed yet today, the streak shown is your count through yesterday so it doesn't drop to 0 before the day's over.
