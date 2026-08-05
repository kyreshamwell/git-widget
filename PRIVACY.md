# Privacy Policy for Pushed

**Last updated:** 5 August 2026

Pushed is a home-screen widget that displays your GitHub contribution graph.

## The short version

Pushed has no servers. It collects nothing, transmits nothing to the developer,
and contains no analytics or advertising SDKs. Your data stays on your device
and travels only to GitHub.

## What Pushed stores, and where

| Data | Where it's stored | Why |
| --- | --- | --- |
| Your GitHub username | On your device, in the app's private storage | To ask GitHub for the right contribution graph |
| Your GitHub personal access token | On your device, in the iOS Keychain | To authenticate that request |
| Your contribution history (the green squares) | On your device, in the app's private storage | So the widget can draw without a network call every time |
| Your reminder preferences | On your device, in the app's private storage | To schedule notifications at the times you chose |

None of this is transmitted to the developer or to any third party. There is no
account to create, and no server operated by the developer at any point.

## Network activity

Pushed makes requests to exactly one address: `api.github.com`, GitHub's public
API. These requests carry your username and access token so GitHub can return
your contribution data. Nothing else leaves your device.

Your use of GitHub is governed by
[GitHub's Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement).

## About the access token

The token Pushed asks for is read-only and scoped to `read:user`, which permits
reading public profile and contribution information. It cannot push code, read
private repositories, or modify your account.

It is held in the iOS Keychain — the same encrypted store iOS uses for saved
passwords — and is shared only with the app's own widget extension so the widget
can refresh itself.

## Notifications

Reminders are scheduled locally by your device. Pushed does not use push
notifications, so no notification data is sent through Apple's servers or any
server operated by the developer.

## Deleting your data

Tapping **Disconnect** in the app erases the stored token, username,
contribution history, and reminder state from your device. Deleting the app
removes everything, including the Keychain entry.

You can revoke the access token itself at any time from
[github.com/settings/tokens](https://github.com/settings/tokens), independently
of this app.

## Children

Pushed is not directed at children under 13 and collects no personal
information from anyone.

## Changes

Any future change to this policy will be published at this URL with an updated
date above.

## Contact

Questions about this policy: **kmshamwell@gmail.com**
