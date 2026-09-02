import AppKit
import MdoroCore

// REQ-COM-003: the AppKit half of the single-instance rule. The decision of what
// counts as "another live instance" is `MdoroCore.SingleInstance.isAnotherLiveInstance`;
// this side only feeds it what the process table reports.
//
// This scan is the only layer. `LSMultipleInstancesProhibited` in Info.plist would refuse
// LaunchServices launches earlier, but LaunchServices enforces it on the test host too —
// same bundle identifier — so `xcodebuild test` dies at launch on any machine where Mdoro
// is running (observed 2026-09-02, on the product owner's). This check covers every launch
// path, including the pair actually hit (Xcode build beside the installed copy), and it can
// step aside under test where the plist key cannot.
extension SingleInstance {

    /// The already-running instance of this app, if there is one.
    @MainActor
    static func existingInstance(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        ownProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) -> NSRunningApplication? {
        guard let bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first {
                isAnotherLiveInstance(
                    bundleIdentifier: $0.bundleIdentifier,
                    processIdentifier: $0.processIdentifier,
                    isTerminated: $0.isTerminated,
                    ownBundleIdentifier: bundleIdentifier,
                    ownProcessIdentifier: ownProcessIdentifier
                )
            }
    }
}
