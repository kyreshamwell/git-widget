#if DEBUG
import Foundation
import WidgetKit

/// Launching with `-PushedDemo` fills the app and the widget with sample data,
/// so every screen can be seen and screenshotted on a simulator with no GitHub
/// account:
///
///     xcrun simctl launch booted com.kyreshamwell.pushed -PushedDemo
///
/// Debug builds only. The fake token lives in memory and never reaches the
/// Keychain, and the next launch without the flag clears the sample data.
enum DemoMode {
    static let username = "your-username"
    private static let activeKey = "debug-demo-mode"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-PushedDemo")
    }

    /// The widget extension never sees the app's launch arguments, so the app
    /// leaves it a note in the shared container instead.
    static var isActive: Bool {
        AppConfig.sharedDefaults.bool(forKey: activeKey)
    }

    static func applyLaunchArguments() {
        let wasActive = isActive
        AppConfig.sharedDefaults.set(isRequested, forKey: activeKey)

        if isRequested {
            ContributionSnapshot.sample().save()
        } else if wasActive {
            // Sample data must not outlive the demo and pass for the real thing.
            AppConfig.sharedDefaults.removeObject(forKey: ContributionSnapshot.defaultsKey)
        }
        if isRequested || wasActive {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
#endif
