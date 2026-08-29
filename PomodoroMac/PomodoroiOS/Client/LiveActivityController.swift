import Foundation
import ActivityKit
import Observation
import MdoroCore

// REQ-UIX-020 / 022 / 028 / Decision 0009: starting, updating and ending the Live Activity.
//
// Starting is for the foreground as a rule (REQ-UIX-020); updating, for while the app is
// running (REQ-UIX-022). Both stay SHOULD on the running gate and suspension, not on which
// start routes exist — do not write an implementation that puts them back to MUST.
// Facts: docs/PLATFORM.md.
//
// Taking `@Observable` off still compiles, but the view stops reading the state back when it
// changes, and **the reason a Live Activity cannot be shown disappears from the screen.**
@MainActor
@Observable
final class LiveActivityController {

    private var activity: Activity<MdoroActivityAttributes>?
    private var startedAt: Date?
    private var lastPushedAt: Date?
    // The content and the deadline last handed over. When the connection drops, only the content is
    // corrected — **the deadline is not pushed out**.
    private var lastState: MdoroActivityAttributes.ContentState?
    private var currentStaleDate: Date?

    // **Always leave a written record of what happened.** "No error" and "never called" are two
    // different things.
    private(set) var diagnostic: String = "Not started yet"
    // Stay quiet while it is working. Put it on the screen only when there is a problem.
    private(set) var isHealthy = false

    // How many Live Activities of this app the OS knows about.
    var systemActivityCount: Int { Activity<MdoroActivityAttributes>.activities.count }

    // REQ-UIX-028: the eight-hour active limit. Past it, a new one is started on return.
    private static let maximumLifetime: TimeInterval = 8 * 60 * 60

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // Funnels into one of start, update or end.
    //
    // `isConnected` is **the caller's connection state right now**. The snapshot's `connection` is the
    // value the Mac told about itself, and it goes on saying "connected" after nothing can be
    // received any more.
    func sync(
        snapshot: StateSnapshot, clockOffset: TimeInterval,
        isForeground: Bool, isConnected: Bool, serverName: String
    ) {
        adoptOrphanedActivity()
        let timer = snapshot.timer

        // REQ-PER-009: end it the moment the state moves to PENDING_DECISION.
        // REQ-UIX-022: end it when the session finishes or is aborted, too.
        guard timer.runState == .running || timer.runState == .paused else {
            diagnostic = "No session running (\(timer.runState.rawValue))"
            isHealthy = true
            end()
            return
        }
        guard let serverStart = timer.sessionStartedAt else {
            diagnostic = "No start time"
            isHealthy = false
            end()
            return
        }

        let state = contentState(
            snapshot: snapshot, serverStart: serverStart,
            clockOffset: clockOffset, isConnected: isConnected
        )

        if let activity {
            if let startedAt, Date().timeIntervalSince(startedAt) > Self.maximumLifetime, isForeground {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                self.activity = nil
                start(state: state, serverName: serverName, isForeground: isForeground, isConnected: isConnected)
                return
            }
            diagnostic = "Updating (\(systemActivityCount) known to the system)"
            isHealthy = true
            push(state, extendingStaleDate: isConnected)
        } else {
            // REQ-UIX-020: what began in the background is started here, on return.
            start(state: state, serverName: serverName, isForeground: isForeground, isConnected: isConnected)
        }
    }

    // REQ-COM-013 / REQ-UIX-024: when not connected, do not make it look operable.
    // REQ-UIX-023: **do not push `staleDate` out.** Nothing has been confirmed, so the deadline
    // arriving is correct.
    func setConnected(_ connected: Bool) {
        guard activity != nil, var state = lastState, state.isConnected != connected else { return }
        state.isConnected = connected
        push(state, extendingStaleDate: false)
    }

    // Whatever is left on the lock screen at launch **cannot be checked against the state as it is
    // now.** Wait a little, and **fold it away if nothing arrives.** If a session is running it is
    // started again right after connecting (REQ-UIX-020).
    func discardOrphansIfUnconfirmed(within delay: TimeInterval = 10) {
        guard activity == nil, !Activity<MdoroActivityAttributes>.activities.isEmpty else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // If a live snapshot arrived in the meantime, it has already been adopted.
            guard let self, self.activity == nil else { return }
            self.diagnostic = "Dismissed a leftover Live Activity: its state could not be confirmed"
            self.isHealthy = true
            self.end()
        }
    }

    // A Live Activity stays on the lock screen even when the process dies.
    // Without picking it up again, **a new one lines up beside the still-frozen old one.**
    private func adoptOrphanedActivity() {
        guard activity == nil else { return }
        let existing = Activity<MdoroActivityAttributes>.activities
        guard let survivor = existing.first else { return }
        activity = survivor
        lastState = survivor.content.state
        // The real start time is gone. REQ-UIX-028's lifetime is measured again from here.
        startedAt = Date()
        lastPushedAt = nil
        // **Do not adopt it without a deadline.** The deadline the previous process left is carried over.
        currentStaleDate = survivor.content.staleDate
        // With two or more, the rest are folded away. **One state must not have two displays.**
        for duplicate in existing.dropFirst() {
            Task { await duplicate.end(nil, dismissalPolicy: .immediate) }
        }
        diagnostic = "Adopted a leftover Live Activity (\(existing.count) found)"
        isHealthy = true
    }

    private func push(_ state: MdoroActivityAttributes.ContentState, extendingStaleDate: Bool) {
        lastState = state
        if extendingStaleDate {
            currentStaleDate = Date().addingTimeInterval(MdoroActivityAttributes.staleAfter)
            lastPushedAt = Date()
        }
        guard let activity else { return }
        // REQ-UIX-023: with no deadline, this very moment becomes the deadline. **Do not leave it
        // without one.**
        let deadline = currentStaleDate ?? Date()
        Task { await activity.update(ActivityContent(state: state, staleDate: deadline)) }
    }

    private func start(
        state: MdoroActivityAttributes.ContentState,
        serverName: String, isForeground: Bool, isConnected: Bool
    ) {
        // **The Mac is the source of truth for the state.** While not connected, what is at hand is no
        // more than "the last value seen". Starting from that leaves **a session that ended long ago
        // sitting on the lock screen, not moving.**
        guard isConnected else {
            diagnostic = String(localized: "Starts once connected to your Mac")
            isHealthy = true
            return
        }
        // REQ-UIX-020: the foreground gate noted at the top of this file.
        guard isForeground else {
            // This is REQ-UIX-020's constraint, not a fault. Do not make a noise about it.
            diagnostic = String(localized: "Can only start while the app is in the foreground")
            isHealthy = true
            return
        }
        guard isSupported else {
            diagnostic = String(localized: "Live Activities are turned off in iOS Settings")
            isHealthy = false
            return
        }
        do {
            let requested = try Activity.request(
                attributes: MdoroActivityAttributes(serverName: serverName),
                content: content(state)
            )
            activity = requested
            startedAt = Date()
            lastPushedAt = Date()
            lastState = state
            currentStaleDate = Date().addingTimeInterval(MdoroActivityAttributes.staleAfter)
            diagnostic = "Started id=\(requested.id.prefix(8)) / \(systemActivityCount) known to the system"
            isHealthy = true
        } catch {
            // REQ-ERR-010 / Decision 0034: **never put the OS's own text straight on the screen.** Its
            // language follows the locale, and it can carry file names and identifiers. This string
            // reaches the iPhone's screen through `ClientModel` (POL-037 of Decision 0035).
            // The diagnostic log is a Mac-only arrangement (Decision 0018), so a code has nowhere to go here.
            // Decision 0035 allowed a code on screen in one place only, the Mac's diagnostic log, so it is dropped.
            diagnostic = String(localized: "Could not start. Check that Live Activities are allowed for Mdoro in iOS Settings")
            isHealthy = false
        }
    }

    // REQ-UIX-023: staleDate is "the time by which there is no guarantee of another check", not the
    // time elapsed. Without keeping this turning, "out of date" shows after 90 seconds even in the
    // foreground with a live connection. Once suspended, this call stops along with everything else
    // and it goes stale, as intended.
    func refreshIfNeeded(
        snapshot: StateSnapshot, clockOffset: TimeInterval,
        isForeground: Bool, isConnected: Bool, serverName: String
    ) {
        guard activity != nil, let lastPushedAt else { return }
        guard Date().timeIntervalSince(lastPushedAt) >= MdoroActivityAttributes.staleRefreshInterval else { return }
        sync(
            snapshot: snapshot, clockOffset: clockOffset,
            isForeground: isForeground, isConnected: isConnected, serverName: serverName
        )
    }

    // **Fold away everything the OS has.** Folding only one leaves the previous process's leftovers
    // sitting there.
    func end() {
        activity = nil
        startedAt = nil
        lastPushedAt = nil
        lastState = nil
        currentStaleDate = nil
        for existing in Activity<MdoroActivityAttributes>.activities {
            Task { await existing.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // REQ-UIX-023: staleDate is set to the time by which there is no guarantee of another check on the state.
    private func content(_ state: MdoroActivityAttributes.ContentState) -> ActivityContent<MdoroActivityAttributes.ContentState> {
        ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(MdoroActivityAttributes.staleAfter)
        )
    }

    private func contentState(
        snapshot: StateSnapshot, serverStart: Date, clockOffset: TimeInterval, isConnected: Bool
    ) -> MdoroActivityAttributes.ContentState {
        let timer = snapshot.timer
        let preset = snapshot.presets.activePreset ?? Preset.standard()

        // REQ-COM-009 / REQ-UIX-026: the extension cannot correct for the clocks, so it is corrected
        // here before being handed over.
        let localStart = serverStart.addingTimeInterval(-clockOffset)
        let localEnd: Date
        var pauseTime: Date?

        switch timer.runState {
        case .paused:
            // REQ-UIX-029: while paused, pauseTime is set to stop the countdown.
            let remaining = TimeInterval(timer.remainingSeconds ?? 0)
            localEnd = Date().addingTimeInterval(remaining)
            pauseTime = Date()
        default:
            localEnd = (timer.sessionEndAt ?? Date()).addingTimeInterval(-clockOffset)
        }

        return MdoroActivityAttributes.ContentState(
            sessionType: timer.sessionType,
            sessionStartedAt: localStart,
            sessionEndAt: localEnd,
            pauseTime: pauseTime,
            loopDisplay: timer.displayLoop(longBreakInterval: preset.longBreakInterval),
            longBreakInterval: preset.longBreakInterval,
            taskName: timer.sessionTaskSnapshot ?? snapshot.task.selectedTaskSnapshot,
            // **Not the connection state inside the snapshot.** What is needed is how this device stands right now.
            isConnected: isConnected
        )
    }
}
