import Foundation

// REQ-COM-003: two instances of this app share one identity.json, so they put the
// same `id` on the air twice — to the iPhone that is not two Macs, it is the same Mac twice,
// and whichever instance answers is "connected". The ruling (2026-09-02): the second launch
// brings the existing process forward and terminates itself.
//
// The decision itself is a predicate over what a process scan reports, and it lives here so
// `swift test` — the only CI — keeps it checked. The scan and the exit are AppKit and belong
// to the Mac app (`SingleInstance.existingInstance()` in PomodoroMac/Services).
public enum SingleInstance {

    /// Whether a scanned process is a second live instance of this app: it carries the same
    /// bundle identifier, it is not this process, and it has not already terminated.
    ///
    /// A `nil` bundle identifier on either side answers `false` — when the app cannot tell
    /// who it is, it must not exit on a guess.
    public static func isAnotherLiveInstance(
        bundleIdentifier: String?,
        processIdentifier: Int32,
        isTerminated: Bool,
        ownBundleIdentifier: String?,
        ownProcessIdentifier: Int32
    ) -> Bool {
        guard let own = ownBundleIdentifier, bundleIdentifier == own else { return false }
        return processIdentifier != ownProcessIdentifier && !isTerminated
    }
}
