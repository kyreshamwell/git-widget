import Foundation

enum BuildEnvironment {
    /// True for Xcode runs and TestFlight installs, false for App Store builds.
    ///
    /// Gating on this rather than `#if DEBUG` is what lets the notification
    /// debug tools ride along to TestFlight — testing reminders means living
    /// with the app on a real phone for days, which a Debug build tethered to
    /// Xcode can't do. App Store builds carry a receipt named `receipt`;
    /// TestFlight builds get `sandboxReceipt`, so the tools drop out of the
    /// public release automatically instead of relying on anyone remembering.
    static var showsDebugTools: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
