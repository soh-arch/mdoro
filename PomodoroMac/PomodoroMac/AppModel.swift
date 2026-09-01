import Foundation
import SwiftUI
import Observation
import MdoroCore

// The state the Mac holds, and the wiring through to MdoroCore.
//
// **The Mac is the source of truth for the state** (the second principle). Every judgement is made
// by `TimerEngine`, and this type does nothing but take the result and carry out the side effects
// (writing the log, notifying, persisting).
@MainActor
@Observable
final class AppModel {

    // MARK: - State

    private(set) var timer: TimerContext
    private(set) var presets: PresetContext
    private(set) var tasks = TaskContext()
    var settings: AppSettings {
        didSet { onSettingsChanged(from: oldValue) }
    }

    // The current time, for display. **Do not put a Timer on the view side**: it does not fire
    // there, and the display freezes.
    private(set) var displayNow = Date()

    // REQ-UIX-004: the connection state.
    private(set) var connection: ConnectionStatus = .disconnected
    // REQ-UIX-033: the UI tells apart a binding that is assigned but has been taken by another app.
    private(set) var pauseResumeHotKeyIsActive = false
    private(set) var showWindowHotKeyIsActive = false
    private(set) var startNextHotKeyIsActive = false
    private(set) var skipHotKeyIsActive = false
    // REQ-SEC-001: the six-digit code shown on the Mac screen while pairing.
    private(set) var pairingCode: String?
    private(set) var pairingRemainingSeconds = 0
    // REQ-SEC-004: a connection request from another client. It waits for the user to approve.
    private(set) var pendingConnectionRequest: String?
    private(set) var serverStartError: String?
    // What to do about it. **It belongs with the sentence above and not with the view**, because
    // the two failures that set `serverStartError` need different answers: a listener that would
    // not come up is usually the local network permission, and records that could not be read are
    // not the user's to fix at all (REQ-COM-003 v2.26).
    private(set) var serverStartHint: String?
    // REQ-NTF-001: if notifications have been turned off on the OS side, put that on the screen.
    private(set) var notificationPermission: NotificationPermission?
    // Why asking for permission failed. An unsigned build stops here.
    private(set) var notificationAuthorizationError: String?

    // REQ-ERR-004 / REQ-LOG-005: put on the UI that writing keeps failing.
    // **Only a write that was attempted and failed reaches here.** REQ-LOG-002 / Decision 0033:
    // a destination nobody has chosen is not a failure, and has `logFolderNotSet` of its own.
    private(set) var logWriteFailed = false
    // REQ-ERR-004: put the reason for the failure on the UI.
    private(set) var lastLogError: String?
    // How many entries have not been written.
    private(set) var pendingLogCount = 0
    // REQ-LOG-002 / Decision 0033: how many carried-over entries were dropped at launch because
    // there was nowhere to write them. Written to the diagnostic log once `start()` opens it.
    private let droppedLogEntryCount: Int
    // When the last successful write happened.
    private(set) var lastLogWriteAt: Date?
    // REQ-TSK-032: say quietly that the selection followed on its own.
    private(set) var didFollowTaskSelection = false

    // REQ-ERR-017 / Decision 0035: a failed restore is shown **once at launch**.
    // Only the user can clear it. Someone who reopened the window without reading it is shown it again.
    private(set) var stateRestoreProblem: String?
    // REQ-ERR-017 / Decision 0036: where it was set aside. **Setting a file aside does not count as done
    // unless where it went is said too.**
    private(set) var stateSetAsidePath: String?
    // REQ-ERR-017 / Decision 0035: a failed save keeps being shown **until it is resolved**.
    // **If saving has been stopped, say that it has been stopped.** On the path where `persist()` bows
    // out at `mayPersist` no failure is raised for the attempt, so without the reason for stopping the
    // status line says nothing. The order lives in MdoroCore.
    var stateSaveProblem: String? {
        PersistenceStatus.problemMessage(
            storeUnavailable: storeUnavailable,
            persistBlockedBy: persistBlockedBy,
            lastSaveFailure: lastSaveFailure
        )
    }

    // MARK: - Dependencies

    private let store: any StateStore
    // POL-047: the notification centre belongs to the OS, so a test needs somewhere else to
    // send to. **The default is the same as production.**
    private let notifications: any SessionNotifying
    // POL-053: holding off idle sleep reaches the whole machine, not this process, so a test
    // needs somewhere else to say it. **The default is the same as production.**
    private let idleSleep: any IdleSleepGuarding
    private let hotKeys = HotKeyCenter()
    // POL-054: built here rather than at the declaration so it can be handed the diagnostic log.
    private let server: MdoroServer
    // REQ-ERR-010 / Decision 0018: a diagnostic log that carries neither task names nor paths.
    let diagnostics: DiagnosticLog
    // Which tab the settings window opens on.
    var settingsTab: SettingsTab = .presets
    // REQ-COM-003 (v2.25): whether the pairing screen (Settings > Connection) is on screen. While
    // it is, the server is up even with nothing paired — it is the one place a pairing can be made.
    private var pairingScreenIsOpen = false
    // REQ-SEC-002 / POL-047: the Keychain is outside this process, so it is a seam like the
    // notification centre and the hold on idle sleep. **The default is the same as production.**
    private let deviceTokens: any DeviceTokenStoring
    // REQ-SEC-002 / Decision 0040: why what is on file must not be written over. **A read that
    // failed is not an empty Keychain** — the records may be sitting there intact, and saving the
    // authenticator's over them is how every pairing disappears at once.
    private var deviceRecordsUnreadable: ErrorCode?
    private var authenticator = Authenticator()
    // REQ-COM-003 / Decision 0040: read on the way to advertising and kept for the life of the
    // process. **Resolved there and not in `init`** — creating it writes a file into Application
    // Support, and this type is built by every test in the Mac target.
    private var serverId: ServerID?
    // POL-047 / REQ-COM-003: where the `id` is kept. **The default is the same as production.**
    // A seam for the same reason the Keychain, the notification centre and the hold on idle sleep
    // are: the suite runs inside MdoroMac.app under its bundle identifier, so `inApplicationSupport()`
    // resolves inside the reader's own container. **It is a closure and not a file** because
    // reaching that folder can fail, and the failure has to arrive where it is decided what to do
    // about it, not at the moment the model is built.
    private let identityFile: () throws -> ServerIdentityFile
    private let logQueue: LogWriteQueue
    private var bookmarks: VaultBookmarks

    private var watcher: FileWatcher?
    private var watchedTaskURL: URL?
    private var tickTask: Task<Void, Never>?
    // POL-114: whether the app has been started. **`start()` is called from a view's `.task`, and a
    // view appears as often as its window is opened** — the reader reopened the main window and got a
    // second server, a second Bonjour registration and a second of everything else `start()` raises.
    // `stop()` puts it back, so a deliberate restart still works; only repetition is refused.
    private var hasStarted = false

    // The place to save to could not be created at all. Every save from here on is lost, so this never resolves.
    private let storeUnavailable: StateStoreError?
    // The most recent failed save. It clears once the next write succeeds.
    private var lastSaveFailure: StateStoreError?
    // A failed restore at launch. The diagnostic log is not open yet, so it is carried over to `start()`
    // and written there.
    private var restoreFailure: StateStoreError?
    // Decision 0036: why the unreadable file could not be set aside. It goes to the diagnostic log.
    private var setAsideFailure: StateStoreError?
    // Decision 0036: what is holding saving back. Either the file could not be set aside, or **I/O did
    // not answer**. The latter sets nothing aside either, so without this the status line says nothing
    // while saving alone stops.
    private let persistBlockedBy: StateStoreError?
    // Decision 0036: not a file that may be written over. **Nothing at all is saved from here on.**
    private var mayPersist: Bool { persistBlockedBy == nil }

    // MARK: - Creation

    // The diagnostic log, the bookmarks, the destination for notifications and the hold on idle sleep
    // are arguments so that this can be verified. **The defaults are the same as production**, and only
    // when they are replaced does this run outside the user's Vault, outside the log the user collects,
    // outside the user's notification centre and off their power settings. The last two are POL-047 and
    // POL-053: the suite runs inside this app, under its bundle identifier, so a request it hands the
    // centre is delivered to the person at the machine — and an activity it begins keeps that machine
    // awake for as long as the run lasts.
    init(
        store: any StateStore,
        now: Date = Date(),
        storeUnavailable: StateStoreError? = nil,
        diagnostics: DiagnosticLog? = nil,
        bookmarks: VaultBookmarks = VaultBookmarks.load(),
        notifications: (any SessionNotifying)? = nil,
        idleSleep: (any IdleSleepGuarding)? = nil,
        deviceTokens: (any DeviceTokenStoring)? = nil,
        identityFile: (() throws -> ServerIdentityFile)? = nil
    ) {
        self.store = store
        self.storeUnavailable = storeUnavailable
        self.deviceTokens = deviceTokens ?? KeychainDeviceTokenStore()
        self.identityFile = identityFile ?? { try ServerIdentityFile.inApplicationSupport() }
        // They cannot be built at the default-value position (DiagnosticLog and NotificationScheduler
        // both live on the MainActor).
        let diagnosticLog = diagnostics ?? DiagnosticLog()
        self.diagnostics = diagnosticLog
        self.notifications = notifications ?? NotificationScheduler()
        self.idleSleep = idleSleep ?? IdleSleepGuard()
        // POL-054: the server writes its refusals to the same log the rest of the app writes to.
        self.server = MdoroServer(diagnostics: diagnosticLog)
        self.bookmarks = bookmarks

        // REQ-ERR-017 / Decision 0035 / 0036: **swallowing a failure cannot be told apart from not failing.**
        // Reading, setting aside and restoring are gathered into one step in MdoroCore (REQ-PRT-001).
        // The order is the point — restore first and save after, and the file that should have been set
        // aside is destroyed.
        let startup = store.loadForStartup(now: now)
        let saved = startup.saved

        self.timer = startup.reduction.context
        self.presets = startup.reduction.presets
        self.settings = saved?.settings ?? .default
        self.tasks = TaskContext(
            selectedTaskId: saved?.selectedTaskId,
            selectedTaskSnapshot: saved?.selectedTaskSnapshot
        )
        // REQ-LOG-005: carry over the log entries that have not been written. **Drop them and they never will be.**
        // REQ-LOG-002 / Decision 0033: unless there is nowhere to write them. Entries an earlier
        // version queued while no folder was set were never meant to exist, and keeping them would
        // pour days of sessions into the file the moment a folder is chosen. The destination is read
        // from the bookmark rather than `settings.logFolderPath`, because the bookmark is what a
        // write actually needs — the path is only what the settings screen shows.
        let carryOver = LogDestination(isConfigured: bookmarks.logFolder != nil)
            .carryOver(saved?.pendingLogEntries ?? [])
        self.logQueue = LogWriteQueue(entries: carryOver.kept)
        self.pendingLogCount = self.logQueue.pendingCount
        self.droppedLogEntryCount = carryOver.dropped
        self.restoreFailure = startup.readFailure
        self.setAsideFailure = startup.setAsideFailure
        self.persistBlockedBy = startup.persistBlockedBy
        self.stateSetAsidePath = startup.setAsideAt?.path
        self.stateRestoreProblem = startup.displayMessage

        // REQ-PER-003(d): when the restore lands on a pending decision, the side effects — cancelling the
        // notifications and so on — are carried out too.
        apply(effects: startup.reduction.effects)
        persist()
    }

    convenience init() {
        // REQ-ERR-017 / Decision 0035: if the place to put it cannot be created at all, **not one** save
        // from here on will succeed. Fall back to memory quietly and nobody notices until they quit.
        do {
            self.init(store: try FileStateStore.inApplicationSupport())
        } catch let error as StateStoreError {
            self.init(store: InMemoryStateStore(), storeUnavailable: error)
        } catch {
            self.init(store: InMemoryStateStore(), storeUnavailable: .ioFailed(ErrorCode(error)))
        }
    }

    // REQ-ERR-017 / Decision 0035: a failed restore is shown once at launch. Only the user can say it has been read.
    func acknowledgeStateRestoreProblem() { stateRestoreProblem = nil }

    // MARK: - Lifecycle

    // POL-114 / REQ-COM-002 / 003: **starting is something the app does once.** The call comes from a
    // view's `.task`, which runs again every time that view appears, and most of what follows had no
    // objection to being run twice: another listener on another port, another Bonjour registration,
    // another `app.start` in the diagnostic log, another request for notification permission.
    //
    // Each step is made safe on its own account as well (the watcher stops before it watches, the tick
    // cancels before it ticks, a hot key unregisters before it registers, and both listeners now fold
    // the previous one). The flag is here because none of that can close the gap the last line opens:
    // `startServer()` is awaited, so two calls arriving in the same turn would both be past every
    // guarded step before either had a listener to guard. This one is decided before anything suspends.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        diagnostics.open(preset: presets.activePreset ?? Preset.standard(), settings: settings)
        diagnostics.write("app.start")
        adoptStoredDeviceTokens()
        writeStartupDiagnostics()
        Task {
            // REQ-ERR-010 / Decision 0034: the screen gets a sentence, the log gets a code.
            switch await notifications.requestAuthorization() {
            case .granted:
                notificationAuthorizationError = nil
            case .notAllowed:
                notificationAuthorizationError = String(
                    localized: "Notifications are turned off for Mdoro. Turn them on in System Settings > Notifications."
                )
                diagnostics.write("notify.authorize", level: .warn, [
                    DiagnosticField("why", ErrorCode.notificationsNotAllowed.summary("notAllowed")),
                ])
            case let .failed(code):
                notificationAuthorizationError = String(
                    localized: "Mdoro could not ask for permission to send notifications. Open System Settings > Notifications and allow them there."
                )
                diagnostics.write("notify.authorize", level: .warn, [
                    DiagnosticField("why", code.summary("requestFailed")),
                ])
            }
            await refreshNotificationPermission()
        }
        // If the destination is usable, write out what could not be written last time, first of all.
        flushLogQueue()
        reloadTasksFromDisk()
        startWatchingTaskFile()
        startTicking()
        syncSideEffectsToState()
        updateHotKey()
        // REQ-COM-003 (v2.25): at launch the server goes up only for a Mac that is paired — or
        // that cannot read whether it is. A Mac with nothing on record raises nothing here: no
        // listener, no name on the LAN, and no local network permission dialog for a feature
        // never used. The dialog arrives when the pairing screen is opened instead, which is the
        // moment it has its context attached (REQ-PLT-007).
        Task { await startServerIfNeeded() }
    }

    // REQ-ERR-010 / Decision 0018: what happened before the log could be opened.
    //
    // `init` runs before `open()`, and a write before that is a no-op, so each of these is held
    // until here. **Kept out of `start()` so that it can be read back on its own** — `start()`
    // raises a listener, a Bonjour registration and a request for notification permission, and
    // none of those belong in a test of what the log says. `start()` is its only other caller.
    func writeStartupDiagnostics() {
        // REQ-ERR-017 / Decision 0035: a failure from before the launch is written the moment the log opens.
        if let restoreFailure {
            diagnostics.write("state.restore", level: .error, [
                DiagnosticField("why", restoreFailure.diagnosticSummary),
            ])
        }
        if let setAsideFailure {
            diagnostics.write("state.setAside", level: .error, [
                DiagnosticField("why", setAsideFailure.diagnosticSummary),
            ])
        }
        if let storeUnavailable {
            diagnostics.write("state.store", level: .error, [
                DiagnosticField("why", storeUnavailable.diagnosticSummary),
            ])
        }
        // REQ-LOG-002 / Decision 0033: entries carried over from a version that queued them with
        // nowhere to write them are dropped, and **dropping records is not done quietly.** Only the
        // count goes in (Decision 0018). It is a warning because something was thrown away, which is
        // not what an unset destination does from here on — that is `log.notRecorded`, at info.
        if droppedLogEntryCount > 0 {
            diagnostics.write("log.dropped", level: .warn, [
                DiagnosticField("count", droppedLogEntryCount),
                DiagnosticField("why", ErrorCode.logFolderNotSet.summary("noFolder")),
            ])
        }
        // The `persist()` in init runs before the log opens. **That one failure was the only one with no record.**
        if let lastSaveFailure {
            diagnostics.write("state.save", level: .error, [
                DiagnosticField("why", lastSaveFailure.diagnosticSummary),
            ])
        }
    }

    // REQ-SEC-002 / Decision 0040: take the records on file into the authenticator.
    //
    // **Kept out of `start()` so that it can be exercised on its own** — the same reason
    // `writeStartupDiagnostics()` is, and `start()` is its only other caller.
    func adoptStoredDeviceTokens() {
        // The tokens live in the Keychain now, and the plist they used to sit in is emptied rather
        // than read. See `LeftoverPlaintextTokens`.
        deviceTokens.eraseLeftoverPlaintext()
        let records = deviceTokens.load()
        // REQ-ERR-010 / Decision 0034: the log gets a code. Losing every pairing on the machine
        // used to leave no trace anywhere.
        if let summary = records.diagnosticSummary {
            diagnostics.write("tokens.load", level: .error, [DiagnosticField("why", summary)])
        }
        deviceRecordsUnreadable = records.unreadableBecause
        authenticator = Authenticator(issuedTokens: records.tokens)
    }

    // REQ-SEC-002 / Decision 0040: **the records go back only when what was there was read.**
    //
    // Both halves of the old route were silent. The save threw its `OSStatus` away after emptying
    // the item, and the load answered `[]` for a Keychain that merely refused to answer — so one
    // pairing made after a bad read replaced every record on file, and the next launch turned
    // every paired iPhone into an unknown one.
    func saveIssuedDeviceTokens() {
        if let unreadable = deviceRecordsUnreadable {
            diagnostics.write("tokens.save", level: .error, [
                DiagnosticField("why", unreadable.summary("notWritten")),
            ])
            return
        }
        if let problem = deviceTokens.save(authenticator.issuedTokens) {
            diagnostics.write("tokens.save", level: .error, [
                DiagnosticField("why", problem.summary("saveFailed")),
            ])
        }
    }

    // REQ-NTF-006 / Decision 0019: send one notification with the chosen settings exactly as they are.
    func sendNotificationSoundTest(_ preset: Preset) {
        notifications.deliverSoundTest(preset: preset)
        diagnostics.write("notify.test", [DiagnosticField("sound", preset.notificationSound.diagnosticValue)])
    }

    func refreshNotificationPermission() async {
        let permission = await notifications.currentPermission()
        guard permission != notificationPermission else { return }
        notificationPermission = permission
        diagnostics.write("notify.permission", level: permission.problem == nil ? .info : .warn, [
            DiagnosticField("status", permission.status),
            DiagnosticField("alert", permission.alertsEnabled),
            DiagnosticField("sound", permission.soundEnabled),
        ])
    }

    // REQ-TIM-001: a countdown for the display, not the source of truth for the time.
    // Run it at exactly one second and the drift in Task.sleep piles up until the display skips, so it
    // runs finer than the granularity shown.
    private static let tickInterval = Duration.milliseconds(250)

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: AppModel.tickInterval)
                await self?.tick()
            }
        }
    }

    func stop() {
        // POL-114: what has been taken down may be raised again. Only repetition is refused, not restart.
        hasStarted = false
        diagnostics.write("app.stop", [DiagnosticField("state", timer.runState.rawValue)])
        tickTask?.cancel()
        tickTask = nil
        stopWatchingTaskFile()
        idleSleep.end()
        hotKeys.unregisterAll()
        stopServer()
    }

    // `now` is an argument so that reaching the end can be reproduced without waiting for it (POL-034).
    // The only call site is `startTicking()`, and that one uses the default `Date()`.
    func tick(now: Date = Date()) {
        // The display moves on even when the state does not change.
        displayNow = now
        updatePairingCountdown(now: now)
        let previousState = timer.runState
        let previousType = timer.sessionType
        let result = TimerEngine.tick(context: timer, presets: presets, settings: settings, now: now)
        guard result.context != timer || !result.effects.isEmpty else { return }

        timer = result.context
        apply(effects: result.effects)
        broadcastState()

        if timer.runState != previousState {
            diagnostics.write("state", [
                DiagnosticField("from", previousState.rawValue),
                DiagnosticField("to", timer.runState.rawValue),
                DiagnosticField("type", previousType.rawValue),
                DiagnosticField("loop", timer.loopCount),
            ])
        }

        // REQ-NTF-001: detect that the end time has been reached, and notify.
        if previousState == .running, timer.runState == .finished {
            let preset = presets.activePreset ?? Preset.standard()
            notifications.notifySessionFinished(
                type: previousType,
                nextType: timer.nextSessionType,
                taskName: timer.sessionTaskSnapshot,
                preset: preset
            )
            diagnostics.write("notify.finished", [
                DiagnosticField("type", previousType.rawValue),
                DiagnosticField("sound", preset.notificationSound.diagnosticValue),
                DiagnosticField("timeSensitive", preset.timeSensitiveNotifications),
            ])
        }
        syncSideEffectsToState()
        persist()
    }

    // REQ-SEC-003: it expires after three minutes. The remaining time on the screen moves along with it.
    private func updatePairingCountdown(now: Date) {
        guard let session = authenticator.pairing else {
            if pairingCode != nil { pairingCode = nil; pairingRemainingSeconds = 0 }
            return
        }
        pairingRemainingSeconds = session.remainingSeconds(now: now)
        if session.isExpired(now: now) { endPairing() }
    }

    // MARK: - Actions

    @discardableResult
    func send(_ action: TimerAction) -> TimerError? {
        let now = Date()
        // Redraw with the time at the instant of the action. Left stale, a value larger than the length
        // shows up right after a start.
        displayNow = now
        switch TimerEngine.reduce(action: action, context: timer, presets: presets, settings: settings, now: now) {
        case let .success(reduction):
            let previousState = timer.runState
            timer = reduction.context
            presets = reduction.presets
            apply(effects: reduction.effects)
            syncSideEffectsToState()
            persist()
            broadcastState()
            diagnostics.write("action", [
                DiagnosticField("do", action.diagnosticName),
                DiagnosticField("from", previousState.rawValue),
                DiagnosticField("to", timer.runState.rawValue),
                DiagnosticField("type", timer.sessionType.rawValue),
                DiagnosticField("loop", timer.loopCount),
                DiagnosticField("task", timer.sessionTaskSnapshot == nil ? "none" : "set"),
            ])
            return nil
        case let .failure(failure):
            // REQ-LOG-018: even when the action is refused, the log committed by the preceding tick is not lost.
            apply(effects: failure.effects)
            persist()
            // A refused action is exactly what gets recorded.
            diagnostics.write("action.rejected", level: .warn, [
                DiagnosticField("do", action.diagnosticName),
                DiagnosticField("state", timer.runState.rawValue),
                DiagnosticField("why", failure.error.diagnosticSummary),
            ])
            return failure.error
        }
    }

    // The remaining time is never held; it is always derived from the absolute time (the third principle).
    func remainingSeconds(at now: Date = Date()) -> Int {
        switch timer.runState {
        case .running:
            guard let endAt = timer.sessionEndAt else { return 0 }
            return max(0, Int(endAt.timeIntervalSince(now).rounded(.up)))
        case .paused:
            return max(0, timer.remainingSeconds ?? 0)
        case .finished, .idle, .pendingDecision:
            return 0
        }
    }

    // MARK: - Side effects

    private func apply(effects: [Effect]) {
        for effect in effects {
            switch effect {
            case let .commitLog(entry):
                enqueueLog(entry)
            case .cancelScheduledNotifications:
                notifications.cancelAll()
            case .endLiveActivity:
                break // the Live Activity is the iPhone's job (8.3 / stage 8)
            }
        }
    }

    private func syncSideEffectsToState() {
        // REQ-PER-006: idle sleep is held off only while RUNNING.
        if timer.runState == .running {
            idleSleep.begin()
        } else {
            idleSleep.end()
        }

        // REQ-NTF-003 / 022: whether the fire time or the content of the notification changes, cancel and reschedule.
        notifications.reschedulePreNotifications(
            preset: presets.activePreset ?? Preset.standard(),
            sessionType: timer.sessionType,
            sessionStartedAt: timer.sessionStartedAt,
            sessionEndAt: timer.runState == .running ? timer.sessionEndAt : nil,
            now: Date()
        )
    }

    private func onSettingsChanged(from previous: AppSettings) {
        guard settings != previous else { return }
        guard settings.isWithinValidRanges() else {
            settings = previous
            diagnostics.write("settings.rejected", level: .warn)
            return
        }
        // The header holds the values from when it opened. When they change, leave one line with the current ones.
        diagnostics.write(
            "settings.change",
            DiagnosticHeader.settingsFields(preset: presets.activePreset ?? Preset.standard(), settings: settings)
        )
        // REQ-PER-004: a change to logicalDayStartHour must not commit PENDING_DECISION on its own.
        send(.updateSettings(settings))
        // If the file name changes, from the next write on it points at the new file.
        if settings.taskFilePath != previous.taskFilePath {
            reloadTasksFromDisk()
            startWatchingTaskFile()
        }
        // 9.5 group C / Decision 0040: the name applies immediately, and the LAN is where it shows.
        if settings.displayName != previous.displayName {
            readvertise()
        }
        if settings.pauseResumeHotKey != previous.pauseResumeHotKey
            || settings.showWindowHotKey != previous.showWindowHotKey
            || settings.startNextHotKey != previous.startNextHotKey
            || settings.skipHotKey != previous.skipHotKey {
            updateHotKey()
        }
        if settings.launchAtLogin != previous.launchAtLogin {
            // If it fails, put the setting back. The UI and what is actually so must not disagree.
            if !LoginItem.setEnabled(settings.launchAtLogin) {
                settings.launchAtLogin = previous.launchAtLogin
            }
        }
        persist()
    }

    // REQ-UIX-033 / Decision 0029: pause, resume, start next and skip, and nothing else.
    // **Nothing is bound to abort or reset.** A destructive action does not belong on a path that
    // cannot stop to ask.
    private func updateHotKey() {
        hotKeys.update(.pauseResume, binding: settings.pauseResumeHotKey) { [weak self] in
            guard let self else { return }
            switch timer.runState {
            case .running: send(.pause)
            case .paused: send(.resume)
            default: break
            }
        }
        hotKeys.update(.showWindow, binding: settings.showWindowHotKey) { [weak self] in
            self?.onShowWindowRequested?()
        }
        hotKeys.update(.startNext, binding: settings.startNextHotKey) { [weak self] in
            self?.startNextSession()
        }
        hotKeys.update(.skip, binding: settings.skipHotKey) { [weak self] in
            guard let self, timer.runState == .running || timer.runState == .paused else { return }
            send(.skip)
        }
        pauseResumeHotKeyIsActive = hotKeys.isRegistered(.pauseResume)
        showWindowHotKeyIsActive = hotKeys.isRegistered(.showWindow)
        startNextHotKeyIsActive = hotKeys.isRegistered(.startNext)
        skipHotKeyIsActive = hotKeys.isRegistered(.skip)
    }

    // Bringing the window forward is the Scene's work. Only the way to call it is held here.
    var onShowWindowRequested: (() -> Void)?

    // Called from the menu and from the hot key alike. The judgement lives in one place.
    func startNextSession() {
        guard let presetId = presets.activePreset?.id else { return }
        let next = timer.nextSessionType
        if next == .work {
            send(.startWork(presetId: presetId, taskSnapshot: tasks.selectedTaskSnapshot))
        } else {
            send(.startBreak(type: next, presetId: presetId))
        }
    }

    // MARK: - Communication (chapter 3 / chapter 10)

    // REQ-COM-003 (v2.25): whether this launch, right now, should have the server up — or, when
    // the records are unreadable, should make the attempt whose refusal reaches the screen.
    // The rule itself lives in MdoroCore (`ServerPresence`), where CI can hold it still.
    private var serverShouldRun: Bool {
        ServerPresence.shouldBeOnTheAir(
            pairingsMayExist: ServerPresence.pairingsMayExist(
                hasPairings: !authenticator.issuedTokens.isEmpty,
                recordsUnreadable: deviceRecordsUnreadable != nil
            ),
            pairingScreenIsOpen: pairingScreenIsOpen
        )
    }

    // REQ-UIX-004 (v2.25): the connection state is shown only while a pairing exists (or while
    // the records that would say so could not be read). A Mac that has never paired is not
    // "Not connected" — it is a Mac in its normal state.
    var showsConnectionState: Bool {
        ServerPresence.showsConnectionState(
            hasPairings: !authenticator.issuedTokens.isEmpty,
            recordsUnreadable: deviceRecordsUnreadable != nil
        )
    }

    // REQ-COM-003 (v2.25): the gate every route to `startServer()` passes, except a rename's
    // deliberate restart (`readvertise`), which is only reachable while the server is up.
    // **Internal so that the decision can be exercised without raising a listener.**
    func startServerIfNeeded() async {
        guard serverShouldRun else { return }
        // Already on the air. `server.start` would fold and re-raise it, dropping whatever is
        // connected — a restart is `readvertise`'s deliberate business, not this gate's.
        guard server.listenPort == nil else { return }
        await startServer()
    }

    // REQ-COM-003 (v2.25): the pairing screen (Settings > Connection) opening is what raises the
    // server for a Mac with nothing paired. REQ-PLT-007: this is also the moment the local
    // network permission dialog appears — in the foreground, in the one context that explains it.
    func pairingScreenOpened() {
        pairingScreenIsOpen = true
        Task { await startServerIfNeeded() }
    }

    // REQ-COM-003 (v2.25): closing the screen takes the server down again — unless a pairing
    // exists, in which case it stays up exactly as it would have at launch.
    func pairingScreenClosed() {
        pairingScreenIsOpen = false
        // The code has no screen to be read from any more (REQ-SEC-001), and the server it was
        // waiting on may be about to fold.
        if authenticator.isPairingActive { endPairing() }
        stopServerIfNotNeeded()
    }

    // REQ-COM-003 (v2.25): the fold behind "the last pairing was deleted" as well as "the pairing
    // screen closed" — the revocation screen (Decision 0040) calls this after removing a record,
    // and the decision of whether anything still needs the server stays in one place.
    func stopServerIfNotNeeded() {
        guard !serverShouldRun else { return }
        stopServer()
    }

    // The deliberate way down. Folding the listener withdraws the Bonjour registration with it.
    private func stopServer() {
        server.stop()
        // POL-140: the port is what `readvertise()` reads to know the Mac is on the air. Left
        // standing, a rename after this fold would re-advertise a listener that no longer exists.
        advertisedWebsocketPort = 0
        // `stop()` cancels the connection without a state callback, so the model's view of it is
        // put right here rather than waited for.
        connection = .disconnected
        authenticator.connectedClientName = nil
        pendingConnectionRequest = nil
        // A deliberate fold is not a failure to listen; whatever failure line was showing is over.
        serverStartError = nil
        serverStartHint = nil
        diagnostics.write("server.stop")
    }

    // **Internal so that the one decision below can be exercised without raising a listener**, the
    // same reason `adoptStoredDeviceTokens()` and `writeStartupDiagnostics()` are.
    func startServer() async {
        // REQ-COM-003 (v2.26): **nothing goes up until this launch knows who it is.** The identity
        // is read before the listener is raised, so the listener is refused too, not only the
        // Bonjour name — a Mac listening on a port nobody can find it at is no better.
        guard let identity = identityToAdvertise() else { return }
        do {
            let websocketPort = try await server.start(callbacks: serverCallbacks())
            // The fold inside `server.start` dropped whatever was connected, without a callback.
            connection = .disconnected
            authenticator.connectedClientName = nil
            // The pairing screen may have closed while the bind was in flight; a server nothing
            // needs does not stay up because it won the race.
            guard serverShouldRun else {
                stopServer()
                return
            }
            advertisedWebsocketPort = websocketPort
            // REQ-COM-002 (v2.25): the registration rides the WebSocket listener itself — the
            // `/info` listener that used to carry it is gone. POL-140: with one listener, the
            // fold-before-bind above means a start that throws leaves nothing advertised.
            server.advertise(displayName: settings.displayName, serverId: identity)
            serverStartError = nil
            serverStartHint = nil
        } catch {
            // A fold that arrived while the bind was in flight cancelled the listener out from
            // under it. That is the fold doing its work, not a failure to listen.
            guard serverShouldRun else { return }
            // REQ-SEC-005 / REQ-ERR-008: the fact that it cannot listen is not hidden.
            // REQ-ERR-010 / Decision 0034: the screen keeps the fact and gives up the reason.
            // The reason is a code now, and `server.start` below is where it goes instead.
            serverStartError = String(localized: "Mdoro cannot listen for iPhone connections.")
            serverStartHint = String(
                localized: "Check that this app is allowed in System Settings > Privacy & Security > Local Network."
            )
            diagnostics.write("server.start", level: .error, [
                DiagnosticField("why", ErrorCode(error).summary("startFailed")),
            ])
        }
    }

    // REQ-COM-003 (v2.26) / REQ-ERR-010: nothing went up, and the reason reaches the screen as
    // well as the log.
    //
    // **The sentence answers the two questions the reader will actually have**: is the pairing
    // gone, and is there anything to do. Neither answer is bad news — the records were left
    // exactly where they are (REQ-SEC-002 / Decision 0036), and a read that was refused once
    // often is not refused next time.
    private func stayOffTheAir(why: String) {
        serverStartError = String(
            localized: "Mdoro is not listening for iPhone connections. It could not read the records that pair this Mac with your iPhone, and going on the air without them would ask every paired iPhone to pair again."
        )
        serverStartHint = String(
            localized: "Nothing was deleted — the records are still there, unread. Quitting Mdoro and opening it again usually clears this."
        )
        diagnostics.write("server.offTheAir", level: .error, [DiagnosticField("why", why)])
    }

    // REQ-COM-003 (v2.27) / REQ-ERR-010: the other way to have no identity — one was made, and
    // the write failed. A different sentence from `stayOffTheAir`, because "nothing was deleted"
    // is not true here in the way that mattered there: nothing is on file at all yet, and no
    // pairing exists to be worried about. What the reader needs is why pairing is refused (a
    // pairing made under an unsaved identity is lost at the next launch) and that relaunching
    // usually clears it — a write that was refused once is rarely refused twice.
    private func stayOffTheAirUnkept(why: String) {
        serverStartError = String(
            localized: "Mdoro is not listening for iPhone connections. It could not save the identity this Mac would be paired under, and a pairing made under an unsaved identity would be lost the next time Mdoro opens."
        )
        serverStartHint = String(
            localized: "Quitting Mdoro and opening it again usually clears this."
        )
        diagnostics.write("server.offTheAir", level: .error, [DiagnosticField("why", why)])
    }

    // Decision 0040: **a rename has to reach the network, or the setting is only half true.**
    // The registration rides the WebSocket listener now (REQ-COM-002 v2.25), and whether
    // reassigning `.service` on a live listener updates the advertisement is not documented
    // anywhere (`docs/PLATFORM.md`), so the listener is raised again instead — the one path
    // measured to withdraw the old name. That fold drops a live connection; the iPhone reconnects
    // on its own (REQ-COM-004), and a rename is a settled act, not something done mid-session.
    // **One at a time.** `startServer` suspends while the new listener comes up, and two of these
    // overlapping would each fold what stood before *they* started: the loser's registration is
    // never cancelled and stays on the network beside the winner's — POL-114 again, from the other
    // direction. The settings screen commits a name once rather than per keystroke, so this is the
    // second guard and not the first.
    private var advertising: Task<Void, Never>?

    private func readvertise() {
        // **A port, not a listener.** What a re-advertisement needs to know is whether the Mac is
        // on the air at all; the listener is the thing it is about to fold and raise again. A Mac
        // that is deliberately off the air (REQ-COM-003 v2.25 — nothing paired, or `stopServer`
        // already ran) keeps its new name to itself until something raises the server again.
        // REQ-COM-003 (v2.26): a port means the id was read at `startServer()`, and `startServer`
        // asks for it again itself — the guard here keeps a rename from being the route that
        // makes a Mac with no readable identity start trying.
        guard advertisedWebsocketPort != 0, identityToAdvertise() != nil else { return }
        let previous = advertising
        advertising = Task {
            await previous?.value
            await startServer()
        }
    }

    // REQ-COM-003 (v2.26): the id this Mac goes on the air under, or nil because it must not go on
    // the air at all.
    //
    // **Two records have to be readable before this Mac says anything on the LAN**: the `id` every
    // paired iPhone files its token under, and the tokens this Mac has issued. A launch that could
    // not read them is not a Mac with nothing paired — it is a Mac that does not know what it has,
    // and on the air it is a stranger. The paired iPhone is asked for a six-digit code, and the
    // token issued in reply is filed under an id that will be gone at the next launch: orphans on
    // both ends. **What could not be read and what is not there are different answers** — the
    // discipline REQ-ERR-017 already applies to `state.json`, applied to identity.
    //
    // The tokens are checked first because that half loses records that are not ours to lose. A
    // Mac holding no records refuses every iPhone that comes back with `unknownDeviceToken`, and
    // the iPhone throws its own token away on being refused (`MdoroClient`). Ours survive the
    // launch; the iPhone's do not.
    //
    // **Internal so that it can be read back without raising a listener**, the same reason
    // `adoptStoredDeviceTokens()` and `writeStartupDiagnostics()` are.
    func identityToAdvertise() -> ServerID? {
        if let unreadable = deviceRecordsUnreadable {
            stayOffTheAir(why: unreadable.summary("tokensUnreadable"))
            return nil
        }
        // Made once, kept in a file of its own beside `state.json`, and read back on every launch
        // (Decision 0040). REQ-COM-003 (v2.27): a Mac that made an id and could not *keep* it
        // does not advertise it — the id is gone at the next launch, so every pairing made under
        // it would be an orphan. The type keeps that honest: `.notKept` carries no id at all.
        if let serverId { return serverId }
        let outcome: ServerIdentityFile.Outcome
        do {
            outcome = try identityFile().loadOrCreate()
        } catch {
            // Application Support could not be reached, so what is in the file is unknown — and
            // unknown is not empty. Inventing an id here is the same failure from one step back.
            outcome = .unreadable(ErrorCode(error))
        }
        switch outcome {
        case let .identified(id):
            serverId = id
            return id
        case let .replaced(id):
            // REQ-ERR-010: replaced is still a failure — whatever was paired under what the file
            // used to say is not coming back — and it is still written down. But broken is not
            // unreadable, so this launch goes on the air (REQ-COM-003 v2.26).
            let why = outcome.diagnosticSummary ?? ErrorCode.identityUnreadable.summary("replaced")
            diagnostics.write("identity.load", level: .error, [DiagnosticField("why", why)])
            serverId = id
            return id
        case let .unreadable(code):
            let why = code.summary("unreadable")
            diagnostics.write("identity.load", level: .error, [DiagnosticField("why", why)])
            stayOffTheAir(why: why)
            return nil
        case let .notKept(code):
            // REQ-COM-003 (v2.27): a failure of the write, so the line is named for the write —
            // `identity.save`, the counterpart of `identity.load` above.
            let why = code.summary("notKept")
            diagnostics.write("identity.save", level: .error, [DiagnosticField("why", why)])
            stayOffTheAirUnkept(why: why)
            return nil
        }
    }

    // POL-047 / REQ-COM-003: **whether a port was ever bound.** Readable from the test target so
    // that the guard at the top of `startServer()` can be shown to stop the listener and not only
    // the Bonjour name; nothing outside this file writes it.
    private(set) var advertisedWebsocketPort: UInt16 = 0

    private func serverCallbacks() -> MdoroServer.Callbacks {
        MdoroServer.Callbacks(
            authenticate: { [weak self] hello in
                guard let self else { return .reject(.connectionRejectedByUser) }
                let decision = authenticator.authenticate(hello, now: Date())
                if case .accept = decision {
                    // REQ-SEC-002 / Decision 0040: the whole record — value, device name and the
                    // date it was issued.
                    saveIssuedDeviceTokens()
                    pairingCode = nil
                } else if case let .needsUserApproval(name) = decision {
                    pendingConnectionRequest = name
                }
                return decision
            },
            handleCommand: { [weak self] command in
                self?.apply(command)
            },
            provideSnapshot: { [weak self] in
                self?.snapshot() ?? StateSnapshot(
                    timer: .idle(now: Date()), task: TaskContext(), settings: .default,
                    presets: .initial(), connection: ConnectionState()
                )
            },
            provideTaskList: { [weak self] in self?.taskListPayload() },
            provideDisplayName: { [weak self] in self?.settings.displayName ?? AppSettings.defaultDisplayName },
            connectionChanged: { [weak self] state in
                guard let self else { return }
                connection = state.isConnected ? .connected : .disconnected
                authenticator.connectedClientName = state.isConnected ? state.peerDeviceName : nil
                // Neither the device name nor the IP is written.
                diagnostics.write("conn", [DiagnosticField("up", state.isConnected)])
            }
        )
    }

    // A received command is translated and handed to the state machine. Whether it is accepted is the
    // state machine's to decide (REQ-ERR-016).
    private func apply(_ command: CommandPayload) {
        // Tasks and settings are outside the state machine's remit. **Fail to catch them here and a
        // selection made on the iPhone is quietly thrown away.**
        switch command.action {
        case .selectTask:
            guard let stableId = command.params?.stableId else {
                reject(.missingParameter(.stableId), command)
                return
            }
            // REQ-TSK-036: a stableId that is not in the current list is not accepted, and the selection
            // is not changed either.
            guard tasks.item(id: stableId) != nil else {
                reject(.taskNotFound, command)
                return
            }
            selectTask(id: stableId)
            return

        case .clearTaskSelection:
            clearTaskSelection()
            return

        case .reloadTasks:
            reloadTasksFromDisk()
            return

        case .updateSettings:
            guard let updated = command.params?.settings else {
                reject(.missingParameter(.settings), command)
                return
            }
            // didSet does the validating, the persisting and the passing on to the state machine together
            settings = updated
            broadcastState()
            return

        default:
            break
        }

        let translated = CommandTranslation.action(
            for: command,
            activePresetId: presets.activePresetId,
            selectedTaskSnapshot: tasks.selectedTaskSnapshot
        )
        switch translated {
        case let .success(action):
            if let error = send(action) { reject(error, command) }
        case let .failure(failure):
            reject(failure, command)
        }
    }

    // 10.2 / Decision 0034 / 0035: `message` is for diagnostics. It is written in the same
    // `case(domain:code)` form as `why` in the diagnostic log. **The receiver looks the wording for the
    // screen up from `code`**, so changing this does not move what the iPhone shows.
    //
    // Taking the failure itself, rather than a code and a sentence, is what keeps that true:
    // no parameter is left for prose, so a call site cannot write one by accident. Three did.
    private func reject(_ failure: CommandTranslation.Failure, _ command: CommandPayload) {
        server.broadcast(.error(ProtocolErrorPayload(
            code: failure.protocolErrorCode,
            message: failure.diagnosticSummary,
            relatedRequestId: command.clientRequestId
        )))
    }

    private func reject(_ error: TimerError, _ command: CommandPayload) {
        server.broadcast(.error(ProtocolErrorPayload(
            code: ProtocolErrorCode(error),
            message: error.diagnosticSummary,
            relatedRequestId: command.clientRequestId
        )))
    }

    private func snapshot() -> StateSnapshot {
        StateSnapshot(
            timer: timer, task: tasks, settings: settings, presets: presets,
            connection: ConnectionState(
                isConnected: connection == .connected,
                lastHeartbeatAt: server.lastHeartbeatAt,
                peerDeviceName: server.connectedDeviceName
            )
        )
    }

    private func taskListPayload() -> TaskListPayload {
        TaskListPayload(
            sections: tasks.grouped(showCompleted: settings.showCompletedTasks)
                .map { TaskListSection(name: $0.name, items: $0.items) },
            parsedAt: Date(),
            sourcePath: settings.taskFilePath,
            itemCount: tasks.items.count,
            isTruncated: tasks.wasTruncated,
            parseError: tasks.loadFailed ? String(localized: "Could not read the task file") : nil
        )
    }

    // REQ-COM-006: sent only when the state changes. The remaining time is not sent every second.
    private func broadcastState() {
        server.broadcast(.stateSnapshot(snapshot()))
    }

    // MARK: - Pairing (REQ-SEC-001 / 003)

    func beginPairing() {
        let code = PairingSession.generateCode()
        authenticator.beginPairing(code: code, now: Date())
        pairingCode = code
        pairingRemainingSeconds = Int(PairingSession.validity)
        // REQ-COM-003 (v2.25): a code with no server behind it can never be entered. Opening the
        // pairing screen already raised one; this is the retry for a raise that failed there.
        Task { await startServerIfNeeded() }
    }

    func endPairing() {
        authenticator.endPairing()
        pairingCode = nil
        pairingRemainingSeconds = 0
    }

    // REQ-SEC-004: only on approval is the existing connection dropped and the new one accepted. The
    // server side times it out.
    func respondToConnectionRequest(approved: Bool) {
        pendingConnectionRequest = nil
        // **Clear it first.** Without that, reauthenticating returns needsUserApproval again and it goes
        // round in circles.
        if approved { authenticator.connectedClientName = nil }
        server.resolvePendingApproval(approved: approved)
    }

    // MARK: - Log

    // REQ-LOG-002 / Decision 0033: where the session log goes, or that nowhere has been chosen.
    // The bookmark is what a write actually needs; `settings.logFolderPath` is only what is shown.
    private var logDestination: LogDestination {
        LogDestination(isConfigured: bookmarks.logFolder != nil)
    }

    // REQ-LOG-002 / Decision 0033: nothing is being recorded, because nowhere has been chosen.
    // **This is not a failure and is shown apart from one** — `logWriteFailed` is for a write that
    // was attempted and refused. The screen has to say this, or the app records nothing in silence.
    var logFolderNotSet: Bool { !logDestination.recordsEntries }

    private func enqueueLog(_ entry: LogEntry) {
        // REQ-LOG-002 / Decision 0033: with nowhere to write it, the entry is neither written nor
        // kept. **Unset is not a failed write**: it never enters the retry queue (REQ-LOG-005) and
        // never counts towards the notification for repeated failures (REQ-ERR-004). The session
        // itself is unaffected — it finished, it counted, and `committedAt` is set (REQ-LOG-019).
        guard logQueue.enqueue(entry, to: logDestination) else {
            // REQ-ERR-010 / Decision 0034: `why` is always `case(domain:code)`. At info, because
            // nothing went wrong: the reader on an issue has to be able to tell this apart from
            // `log.write` failing, and a warning would say exactly the thing Decision 0033 denies.
            diagnostics.write("log.notRecorded", [
                DiagnosticField("why", ErrorCode.logFolderNotSet.summary("noFolder")),
            ])
            return
        }
        pendingLogCount = logQueue.pendingCount
        flushLogQueue()
    }

    func flushLogQueue() {
        // REQ-LOG-002 / Decision 0033: **with no folder chosen there is nothing here to write.**
        // Nothing was queued while it was unset, and nothing was carried over from before, so this
        // returns quietly rather than reporting — an unset destination is not a failed write. It
        // used to raise `logWriteFailed`, keep the entry and count towards REQ-ERR-004's threshold.
        guard let bookmark = bookmarks.logFolder else { return }
        guard logQueue.pendingCount > 0 else { return }
        let options = LogFormatter.Options(taskAsLink: settings.logTaskAsLink)

        do {
            let fileName = settings.logFileName
            let result = try VaultFileAccess.withAccess(to: bookmark) { folderURL -> LogWriteQueue.FlushResult in
                let logURL = folderURL.appendingPathComponent(fileName)
                // REQ-LOG-021 / the first principle: Task.md is never the destination of a write. It is
                // checked on every write.
                let taskURL = bookmarks.taskFile.flatMap { try? VaultFileAccess.resolve($0).url }
                let writer = LogWriter(fileURL: logURL, taskFileURL: taskURL, options: options)
                return logQueue.flush { try writer.append($0) }
            }
            logWriteFailed = result.pending > 0
            pendingLogCount = result.pending
            if result.written > 0 {
                lastLogWriteAt = Date()
                persist()
            }
            // REQ-ERR-010 / Decision 0034: a sentence for the screen, a code for the log.
            lastLogError = result.lastError?.displayMessage
            // **This is the evidence that it was written.**
            diagnostics.write("log.write", level: result.pending > 0 ? .warn : .info, [
                DiagnosticField("written", result.written),
                DiagnosticField("pending", result.pending),
                DiagnosticField("file", DiagnosticRedaction.optionalDigest(settings.logFolderPath)),
                DiagnosticField("why", result.lastError?.diagnosticSummary ?? "-"),
            ])
            // REQ-ERR-004 / Decision 0039: notify once three writes have failed — three in a row,
            // or three of the last ten attempts.
            if result.shouldNotify {
                notifications.notifyLogWriteFailure()
            }
        } catch {
            // **Nothing fails quietly.**
            // Only bookmark resolution and starting access land here (VaultFileAccess).
            // REQ-ERR-010 / Decision 0034: keep the domain and the code, never the OS text.
            logWriteFailed = true
            let failure = error as? VaultFileAccess.AccessError
            lastLogError = failure?.displayMessage ?? String(
                localized: "The session log could not be written. Check the folder set in Settings; unwritten entries stay queued."
            )
            diagnostics.write("log.write", level: .error, [
                DiagnosticField("written", 0),
                DiagnosticField("pending", logQueue.pendingCount),
                DiagnosticField("why", failure?.diagnosticSummary ?? ErrorCode(error).summary("unexpected")),
            ])
        }
    }

    // MARK: - Tasks

    func reloadTasksFromDisk() {
        guard let bookmark = bookmarks.taskFile else { return }
        // REQ-ERR-002: on failure the last list that succeeded is kept. It is not overwritten with an empty list.
        let result: Result<TaskParseResult, Error>
        do {
            result = .success(try VaultFileAccess.withAccess(to: bookmark) { url in
                try TaskFileReader(fileURL: url).read()
            })
        } catch {
            result = .failure(error)
        }
        let outcome = TaskReloader.reload(previous: tasks, result: result)
        tasks = outcome.context
        didFollowTaskSelection = outcome.didFollow
        // Only the counts are kept.
        diagnostics.write("task.reload", level: outcome.context.loadFailed ? .warn : .info, [
            DiagnosticField("count", outcome.context.items.count),
            DiagnosticField("failed", outcome.context.loadFailed),
            DiagnosticField("truncated", outcome.context.wasTruncated),
            DiagnosticField("followed", outcome.didFollow),
            DiagnosticField("file", DiagnosticRedaction.optionalDigest(settings.taskFilePath)),
        ])
        persist()
        // REQ-TSK-002: when a change is detected, the latest list goes out to the iPhone.
        server.broadcast(.taskList(taskListPayload()))
        broadcastState()
    }

    func selectTask(id: String) {
        var updated = tasks
        guard (try? updated.select(id: id)) != nil else { return }
        tasks = updated
        send(.selectTask(snapshot: updated.selectedTaskSnapshot))
        broadcastState()
    }

    func clearTaskSelection() {
        tasks.clearSelection()
        send(.clearTaskSelection)
        broadcastState()
    }

    func acknowledgeTaskFollow() { didFollowTaskSelection = false }

    // MARK: - File watching

    private func startWatchingTaskFile() {
        stopWatchingTaskFile()
        guard let bookmark = bookmarks.taskFile,
              let url = try? VaultFileAccess.beginAccess(to: bookmark) else { return }
        watchedTaskURL = url

        // REQ-TSK-002 / REQ-PLT-006: watch the parent directory with a 300ms debounce.
        let watcher = FileWatcher(fileURL: url) { [weak self] in
            Task { @MainActor in self?.reloadTasksFromDisk() }
        }
        try? watcher.start()
        self.watcher = watcher
    }

    private func stopWatchingTaskFile() {
        watcher?.stop()
        watcher = nil
        // REQ-PLT-005: start and stop are paired.
        if let watchedTaskURL {
            VaultFileAccess.endAccess(to: watchedTaskURL)
            self.watchedTaskURL = nil
        }
    }

    // MARK: - Choosing files

    func setTaskFile(_ url: URL) {
        // REQ-PLT-003: created as read-only, which makes writing impossible at the OS level.
        guard let data = try? VaultFileAccess.readOnlyBookmark(for: url) else { return }
        bookmarks.taskFile = data
        bookmarks.save()
        settings.taskFilePath = url.path
    }

    // Decision 0015: the destination is a **folder**. An atomic write (REQ-LOG-004 / REQ-PLT-004) needs
    // permission to create a temporary file.
    func setLogFolder(_ url: URL) throws {
        // REQ-LOG-021: the same file as Task.md cannot be chosen.
        let taskURL = bookmarks.taskFile.flatMap { try? VaultFileAccess.resolve($0).url }
        let candidate = url.appendingPathComponent(settings.logFileName)
        try LogWriter.validate(logFileURL: candidate, taskFileURL: taskURL)

        guard let data = try? VaultFileAccess.readWriteBookmark(for: url) else {
            throw VaultFileAccess.AccessError.bookmarkCreationFailed
        }
        bookmarks.logFolder = data
        bookmarks.save()
        settings.logFolderPath = url.path
        // REQ-LOG-005: a write that failed while a folder *was* set is still queued, and choosing
        // the folder again is how the user is told to fix it. So the retry belongs here.
        // REQ-LOG-002 / Decision 0033: **and nothing accumulates while no folder is set**, so this
        // can no longer pour days of unasked-for sessions into the file at the moment one is chosen.
        flushLogQueue()
    }

    // MARK: - Persistence

    // REQ-PER-001: persisted every time the state changes.
    // REQ-ERR-017 / Decision 0035: a failure to write stays on the screen until writing works again.
    private func persist() {
        // Decision 0036: a file that could not be set aside is never written over, not once.
        // **Being unreadable and being safe to destroy are not the same thing.** That it has stopped is
        // what the status line keeps saying.
        guard mayPersist else { return }
        do {
            try store.save(
                PersistedState(
                    timer: timer,
                    presets: presets,
                    settings: settings,
                    selectedTaskId: tasks.selectedTaskId,
                    selectedTaskSnapshot: tasks.selectedTaskSnapshot,
                    pendingLogEntries: logQueue.pendingEntries,
                    savedAt: Date()
                )
            )
            lastSaveFailure = nil
        } catch {
            // REQ-ERR-010 / Decision 0034: a sentence for the screen, a code for the log.
            let failure = (error as? StateStoreError) ?? .ioFailed(ErrorCode(error))
            lastSaveFailure = failure
            diagnostics.write("state.save", level: .error, [
                DiagnosticField("why", failure.diagnosticSummary),
            ])
        }
    }
}
