import Foundation
import SwiftUI
import Observation
import MdoroCore

// Mac 側の状態保持と、MdoroCore への配線。
//
// **状態の正本は Mac である**（3原則の2つ目）。判断はすべて `TimerEngine` が行い、
// ここは結果を受けて副作用（ログ書き込み・通知・永続化）を実行する係に徹する。
@MainActor
@Observable
final class AppModel {

    // MARK: - 状態

    private(set) var timer: TimerContext
    private(set) var presets: PresetContext
    private(set) var tasks = TaskContext()
    var settings: AppSettings {
        didSet { onSettingsChanged(from: oldValue) }
    }

    // 表示用の現在時刻。**ビュー側に Timer を持たせない**（発火せず表示が固まる）。
    private(set) var displayNow = Date()

    // REQ-UIX-004: 接続状態。
    private(set) var connection: ConnectionStatus = .disconnected
    // REQ-UIX-033: 割り当ててあるのに他アプリに取られている場合を UI で区別する。
    private(set) var pauseResumeHotKeyIsActive = false
    private(set) var showWindowHotKeyIsActive = false
    private(set) var startNextHotKeyIsActive = false
    private(set) var skipHotKeyIsActive = false
    // REQ-SEC-001: ペアリング中に Mac 画面へ表示する6桁コード。
    private(set) var pairingCode: String?
    private(set) var pairingRemainingSeconds = 0
    // REQ-SEC-004: 別のクライアントからの接続要求。ユーザーの承認を待つ。
    private(set) var pendingConnectionRequest: String?
    private(set) var serverStartError: String?
    // REQ-NTF-001: 通知が OS 側で切られていたら、それを画面に出す。
    private(set) var notificationPermission: NotificationPermission?
    // 許可を求めることに失敗した理由。署名の無いビルドではここで止まる。
    private(set) var notificationAuthorizationError: String?

    // REQ-ERR-004 / REQ-LOG-005: 書き込みに失敗し続けていることを UI に出す。
    private(set) var logWriteFailed = false
    // REQ-ERR-004: 失敗の理由を UI に出す。
    private(set) var lastLogError: String?
    // 書けていない件数。
    private(set) var pendingLogCount = 0
    // 直近に書き込めた時刻。
    private(set) var lastLogWriteAt: Date?
    // REQ-TSK-032: 選択が自動追従したことを控えめに知らせる。
    private(set) var didFollowTaskSelection = false

    // REQ-ERR-017 / Decision 0035: 復元の失敗は**起動時に1度**示す。
    // 消せるのは利用者だけ。読まずに窓を開き直した人にもう一度出す。
    private(set) var stateRestoreProblem: String?
    // REQ-ERR-017 / Decision 0036: 退避先。**どこへ行ったかまで言わないと退避したことにならない。**
    private(set) var stateSetAsidePath: String?
    // REQ-ERR-017 / Decision 0035: 保存の失敗は**解消するまで**出し続ける。
    // **保存を止めたなら、止めたと言う。** `persist()` が `mayPersist` で降りる経路では
    // 都度の失敗が立たないので、止めた理由を渡さないとステータス行が黙る。順序は MdoroCore 側。
    var stateSaveProblem: String? {
        PersistenceStatus.problemMessage(
            storeUnavailable: storeUnavailable,
            persistBlockedBy: persistBlockedBy,
            lastSaveFailure: lastSaveFailure
        )
    }

    // MARK: - 依存

    private let store: any StateStore
    private let notifications = NotificationScheduler()
    private let idleSleepGuard = IdleSleepGuard()
    private let hotKeys = HotKeyCenter()
    private let server = MdoroServer()
    // REQ-ERR-010 / Decision 0018: タスク名もパスも載せない診断ログ。
    let diagnostics: DiagnosticLog
    // 設定ウィンドウをどのタブで開くか。
    var settingsTab: SettingsTab = .presets
    private var infoServer: InfoHTTPServer?
    private var authenticator = Authenticator(issuedTokens: DeviceTokenStore.load())
    private let logQueue: LogWriteQueue
    private var bookmarks: VaultBookmarks

    private var watcher: FileWatcher?
    private var watchedTaskURL: URL?
    private var tickTask: Task<Void, Never>?

    // 保存先そのものが作れなかった。以降の保存はすべて失われるので、解消はしない。
    private let storeUnavailable: StateStoreError?
    // 直近の保存の失敗。次に書けたら消える。
    private var lastSaveFailure: StateStoreError?
    // 起動時の復元の失敗。診断ログはまだ開いていないので、`start()` まで持ち越して書く。
    private var restoreFailure: StateStoreError?
    // Decision 0036: 読めないファイルを退避できなかった理由。診断ログへ書く。
    private var setAsideFailure: StateStoreError?
    // Decision 0036: 保存を止めている理由。退避できなかった場合と、**I/O が応答しなかった場合**。
    // 後者は退避もしないので、これが無いとステータス行が何も言わないまま保存だけ止まる。
    private let persistBlockedBy: StateStoreError?
    // Decision 0036: 上に書いてよいファイルではない。**以降いっさい保存しない。**
    private var mayPersist: Bool { persistBlockedBy == nil }

    // MARK: - 生成

    // 診断ログとブックマークを引数に取るのは検証のため。**既定は本番と同じ**で、
    // 差し替えたときだけ、利用者の Vault と利用者が集めるログの外で動く。
    init(
        store: any StateStore,
        now: Date = Date(),
        storeUnavailable: StateStoreError? = nil,
        diagnostics: DiagnosticLog? = nil,
        bookmarks: VaultBookmarks = VaultBookmarks.load()
    ) {
        self.store = store
        self.storeUnavailable = storeUnavailable
        // 既定値の位置では組み立てられない（DiagnosticLog は MainActor 上にある）。
        self.diagnostics = diagnostics ?? DiagnosticLog()
        self.bookmarks = bookmarks

        // REQ-ERR-017 / Decision 0035 / 0036: **握り潰しは、失敗しないことと区別がつかない。**
        // 読み込み・退避・復元は MdoroCore の1手順にまとまっている（REQ-PRT-001）。
        // 順序が要点である — 先に復元して後から保存すると、退避すべきファイルを潰す。
        let startup = store.loadForStartup(now: now)
        let saved = startup.saved

        self.timer = startup.reduction.context
        self.presets = startup.reduction.presets
        self.settings = saved?.settings ?? .default
        self.tasks = TaskContext(
            selectedTaskId: saved?.selectedTaskId,
            selectedTaskSnapshot: saved?.selectedTaskSnapshot
        )
        // REQ-LOG-005: 書き込めていないログを引き継ぐ。**捨てると二度と書かれない。**
        self.logQueue = LogWriteQueue(entries: saved?.pendingLogEntries ?? [])
        self.pendingLogCount = self.logQueue.pendingCount
        self.restoreFailure = startup.readFailure
        self.setAsideFailure = startup.setAsideFailure
        self.persistBlockedBy = startup.persistBlockedBy
        self.stateSetAsidePath = startup.setAsideAt?.path
        self.stateRestoreProblem = startup.displayMessage

        // REQ-PER-003(d): 復元で判断待ちになった場合、通知の取り消しなどの副作用も実行する。
        apply(effects: startup.reduction.effects)
        persist()
    }

    convenience init() {
        // REQ-ERR-017 / Decision 0035: 置き場所ごと作れないなら、以降の保存は**一度も**成功しない。
        // 黙ってメモリへ落とすと、終了するまで気づけない。
        do {
            self.init(store: try FileStateStore.inApplicationSupport())
        } catch let error as StateStoreError {
            self.init(store: InMemoryStateStore(), storeUnavailable: error)
        } catch {
            self.init(store: InMemoryStateStore(), storeUnavailable: .ioFailed(ErrorCode(error)))
        }
    }

    // REQ-ERR-017 / Decision 0035: 復元の失敗は起動時に1度。読んだと言えるのは利用者だけ。
    func acknowledgeStateRestoreProblem() { stateRestoreProblem = nil }

    // MARK: - ライフサイクル

    func start() {
        diagnostics.open(preset: presets.activePreset ?? Preset.standard(), settings: settings)
        diagnostics.write("app.start")
        // REQ-ERR-017 / Decision 0035: 起動より前に起きた失敗は、ログが開いた時点で書く。
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
        // init の `persist()` はログが開く前に走る。**そこで落ちた1件だけ記録が無かった。**
        if let lastSaveFailure {
            diagnostics.write("state.save", level: .error, [
                DiagnosticField("why", lastSaveFailure.diagnosticSummary),
            ])
        }
        Task {
            // REQ-ERR-010 / Decision 0034: the screen gets a sentence, the log gets a code.
            switch await notifications.requestAuthorization() {
            case .granted:
                notificationAuthorizationError = nil
            case .notAllowed:
                notificationAuthorizationError =
                    "Notifications are turned off for Mdoro. Turn them on in System Settings > Notifications."
                diagnostics.write("notify.authorize", level: .warn, [
                    DiagnosticField("why", ErrorCode.notificationsNotAllowed.summary("notAllowed")),
                ])
            case let .failed(code):
                notificationAuthorizationError =
                    "Mdoro could not ask for permission to send notifications. Open System Settings > Notifications and allow them there."
                diagnostics.write("notify.authorize", level: .warn, [
                    DiagnosticField("why", code.summary("requestFailed")),
                ])
            }
            await refreshNotificationPermission()
        }
        // 前回書けなかったぶんを、出力先が使えるなら真っ先に書き出す。
        flushLogQueue()
        reloadTasksFromDisk()
        startWatchingTaskFile()
        startTicking()
        syncSideEffectsToState()
        updateHotKey()
        Task { await startServer() }
    }

    // REQ-NTF-006 / Decision 0019: 選んだ設定のまま通知を1件送る。
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

    // REQ-TIM-001: 表示のためのカウントダウンであって、時間の正本ではない。
    // 1秒ちょうどで回すと Task.sleep のずれが積もって表示が飛ぶので、粒度より細かく回す。
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
        diagnostics.write("app.stop", [DiagnosticField("state", timer.runState.rawValue)])
        tickTask?.cancel()
        tickTask = nil
        stopWatchingTaskFile()
        idleSleepGuard.end()
        hotKeys.unregisterAll()
        server.stop()
        infoServer?.stop()
    }

    // `now` を引数に取るのは、終了への到達を待たずに再現するため（POL-034）。
    // 呼び出し口は `startTicking()` だけで、そこは既定の `Date()` を使う。
    func tick(now: Date = Date()) {
        // 状態が変わらなくても表示は進める。
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

        // REQ-NTF-001: 終了時刻への到達を検知して通知する。
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

    // REQ-SEC-003: 3分で失効する。画面の残り時間も一緒に進める。
    private func updatePairingCountdown(now: Date) {
        guard let session = authenticator.pairing else {
            if pairingCode != nil { pairingCode = nil; pairingRemainingSeconds = 0 }
            return
        }
        pairingRemainingSeconds = session.remainingSeconds(now: now)
        if session.isExpired(now: now) { endPairing() }
    }

    // MARK: - 操作

    @discardableResult
    func send(_ action: TimerAction) -> TimerError? {
        let now = Date()
        // 操作した瞬間の時刻で描き直す。古いままだと開始直後に長さより大きい値が出る。
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
            // REQ-LOG-018: 拒否されても、直前の tick が確定させたログは失わない。
            apply(effects: failure.effects)
            persist()
            // 拒否された操作こそ記録する。
            diagnostics.write("action.rejected", level: .warn, [
                DiagnosticField("do", action.diagnosticName),
                DiagnosticField("state", timer.runState.rawValue),
                DiagnosticField("why", failure.error.diagnosticSummary),
            ])
            return failure.error
        }
    }

    // 残り時間は保持せず、常に絶対時刻から求める（3原則の3つ目）。
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

    // MARK: - 副作用

    private func apply(effects: [Effect]) {
        for effect in effects {
            switch effect {
            case let .commitLog(entry):
                enqueueLog(entry)
            case .cancelScheduledNotifications:
                notifications.cancelAll()
            case .endLiveActivity:
                break // Live Activity は iPhone 側の担当（8.3 / 工程8）
            }
        }
    }

    private func syncSideEffectsToState() {
        // REQ-PER-006: RUNNING の間だけアイドルスリープを抑止する。
        if timer.runState == .running {
            idleSleepGuard.begin()
        } else {
            idleSleepGuard.end()
        }

        // REQ-NTF-003 / 022: 発火時刻と通知内容のどちらが変わっても、取り消して再スケジュールする。
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
        // ヘッダは開いたときの値。変わったら現在値を1行残す。
        diagnostics.write(
            "settings.change",
            DiagnosticHeader.settingsFields(preset: presets.activePreset ?? Preset.standard(), settings: settings)
        )
        // REQ-PER-004: logicalDayStartHour の変更で PENDING_DECISION を自動確定させない。
        send(.updateSettings(settings))
        // ファイル名が変われば、次の書き込みから新しいファイルへ向く。
        if settings.taskFilePath != previous.taskFilePath {
            reloadTasksFromDisk()
            startWatchingTaskFile()
        }
        if settings.pauseResumeHotKey != previous.pauseResumeHotKey
            || settings.showWindowHotKey != previous.showWindowHotKey
            || settings.startNextHotKey != previous.startNextHotKey
            || settings.skipHotKey != previous.skipHotKey {
            updateHotKey()
        }
        if settings.launchAtLogin != previous.launchAtLogin {
            // 失敗したら設定を戻す。UI と実態を食い違わせない。
            if !LoginItem.setEnabled(settings.launchAtLogin) {
                settings.launchAtLogin = previous.launchAtLogin
            }
        }
        persist()
    }

    // REQ-UIX-033 / Decision 0029: 一時停止・再開・次を開始・スキップのみ。
    // **中断とリセットは割り当てない。** 確認をはさめない経路に破壊的操作を置かない。
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

    // ウィンドウを前面に出すのは Scene 側の仕事。呼び出し口だけ持つ。
    var onShowWindowRequested: (() -> Void)?

    // メニューからもホットキーからも呼ぶ。判断を1箇所に置く。
    func startNextSession() {
        guard let presetId = presets.activePreset?.id else { return }
        let next = timer.nextSessionType
        if next == .work {
            send(.startWork(presetId: presetId, taskSnapshot: tasks.selectedTaskSnapshot))
        } else {
            send(.startBreak(type: next, presetId: presetId))
        }
    }

    // MARK: - 通信 (第3章 / 第10章)

    private func startServer() async {
        do {
            let websocketPort = try await server.start(callbacks: serverCallbacks())
            // REQ-COM-002 / 003: Bonjour で広告し、`GET /info` でサーバー情報を返す。
            let info = InfoHTTPServer(info: serverInfo(websocketPort: websocketPort))
            try await info.start()
            info.advertise(serviceName: Host.current().localizedName ?? "Mdoro", websocketPort: websocketPort)
            infoServer = info
            websocketPortForInfo = websocketPort
            serverStartError = nil
        } catch {
            // REQ-SEC-005 / REQ-ERR-008: 待ち受けられない事実を隠さない。
            // REQ-ERR-010 / Decision 0034: the screen keeps the fact and gives up the reason.
            // The reason is a code now, and `server.start` below is where it goes instead.
            serverStartError = "Mdoro cannot listen for iPhone connections."
            diagnostics.write("server.start", level: .error, [
                DiagnosticField("why", ErrorCode(error).summary("startFailed")),
            ])
        }
    }

    private var websocketPortForInfo: UInt16 = 0

    private func serverInfo(websocketPort: UInt16) -> ServerInfo {
        ServerInfo(
            serverName: Host.current().localizedName ?? "Mac",
            protocolVersion: PomodoroProtocol.version,
            isPairingMode: pairingCode != nil,
            websocketPort: websocketPort
        )
    }

    // ペアリングの開始・終了で `/info` の内容が変わる。**押し込み忘れると iPhone の表示が狂う。**
    private func refreshServerInfo() {
        infoServer?.update(serverInfo(websocketPort: websocketPortForInfo))
    }

    private func serverCallbacks() -> MdoroServer.Callbacks {
        MdoroServer.Callbacks(
            authenticate: { [weak self] hello in
                guard let self else { return .reject(.connectionRejectedByUser) }
                let decision = authenticator.authenticate(hello, now: Date())
                if case let .accept(token) = decision {
                    DeviceTokenStore.save(authenticator.issuedTokens)
                    _ = token
                    pairingCode = nil
                    refreshServerInfo()
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
            connectionChanged: { [weak self] state in
                guard let self else { return }
                connection = state.isConnected ? .connected : .disconnected
                authenticator.connectedClientName = state.isConnected ? state.peerDeviceName : nil
                // 端末名も IP も書かない。
                diagnostics.write("conn", [DiagnosticField("up", state.isConnected)])
            }
        )
    }

    // 受け取ったコマンドは翻訳して状態機械へ渡す。可否は状態機械が決める（REQ-ERR-016）。
    private func apply(_ command: CommandPayload) {
        // タスクと設定は状態機械の管轄外。**ここで受け止めないと iPhone からの選択が黙って捨てられる。**
        switch command.action {
        case .selectTask:
            guard let stableId = command.params?.stableId else {
                reject(.invalidStateForAction, "No stableId", command)
                return
            }
            // REQ-TSK-036: 現在の一覧に存在しない stableId は受け付けず、選択も変えない。
            guard tasks.item(id: stableId) != nil else {
                reject(.taskNotFound, "That task no longer exists", command)
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
                reject(.invalidStateForAction, "No settings", command)
                return
            }
            // didSet が検証・永続化・状態機械への反映をまとめて行う
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
        // 10.2 / Decision 0034 / 0035: `message` は診断用。診断ログの `why` と同じ
        // `case(domain:code)` で書く。**画面の文言は受け取る側が `code` から引く**ので、
        // ここを変えても iPhone の表示は動かない。
        switch translated {
        case let .success(action):
            if let error = send(action) {
                server.broadcast(.error(ProtocolErrorPayload(
                    code: ProtocolErrorCode(error),
                    message: error.diagnosticSummary,
                    relatedRequestId: command.clientRequestId
                )))
            }
        case let .failure(failure):
            server.broadcast(.error(ProtocolErrorPayload(
                code: failure.protocolErrorCode,
                message: failure.diagnosticSummary,
                relatedRequestId: command.clientRequestId
            )))
        }
    }

    private func reject(_ code: ProtocolErrorCode, _ message: String, _ command: CommandPayload) {
        server.broadcast(.error(ProtocolErrorPayload(
            code: code, message: message, relatedRequestId: command.clientRequestId
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
            parseError: tasks.loadFailed ? "Could not read the task file" : nil
        )
    }

    // REQ-COM-006: 状態が変化したときだけ送る。残り時間は毎秒送らない。
    private func broadcastState() {
        server.broadcast(.stateSnapshot(snapshot()))
    }

    // MARK: - ペアリング (REQ-SEC-001 / 003)

    func beginPairing() {
        let code = PairingSession.generateCode()
        authenticator.beginPairing(code: code, now: Date())
        pairingCode = code
        pairingRemainingSeconds = Int(PairingSession.validity)
        refreshServerInfo()
    }

    func endPairing() {
        authenticator.endPairing()
        pairingCode = nil
        pairingRemainingSeconds = 0
        refreshServerInfo()
    }

    // REQ-SEC-004: 承認された場合のみ既存接続を切って受け入れる。タイムアウトはサーバー側が計る。
    func respondToConnectionRequest(approved: Bool) {
        pendingConnectionRequest = nil
        // **先に空けておく。** 空けないと再認証がまた needsUserApproval を返して堂々巡りになる。
        if approved { authenticator.connectedClientName = nil }
        server.resolvePendingApproval(approved: approved)
    }

    // MARK: - ログ

    private func enqueueLog(_ entry: LogEntry) {
        logQueue.enqueue(entry)
        pendingLogCount = logQueue.pendingCount
        flushLogQueue()
    }

    func flushLogQueue() {
        guard logQueue.pendingCount > 0 else { return }
        let options = LogFormatter.Options(taskAsLink: settings.logTaskAsLink)

        guard let bookmark = bookmarks.logFolder else {
            // 出力先が未設定でも記録は捨てず、キューへ残す。
            logWriteFailed = true
            lastLogError = "No folder is set for the session log. Choose one in Settings; entries stay queued until then."
            // REQ-ERR-010 / Decision 0034: `why` is always `case(domain:code)`.
            diagnostics.write("log.blocked", level: .warn, [
                DiagnosticField("why", ErrorCode.logFolderNotSet.summary("noFolder")),
                DiagnosticField("pending", logQueue.pendingCount),
            ])
            return
        }

        do {
            let fileName = settings.logFileName
            let result = try VaultFileAccess.withAccess(to: bookmark) { folderURL -> LogWriteQueue.FlushResult in
                let logURL = folderURL.appendingPathComponent(fileName)
                // REQ-LOG-021 / 第1原則: Task.md を書き込み先にしない。書き込みのたびに確かめる。
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
            // **書いたことの証拠になる。**
            diagnostics.write("log.write", level: result.pending > 0 ? .warn : .info, [
                DiagnosticField("written", result.written),
                DiagnosticField("pending", result.pending),
                DiagnosticField("file", DiagnosticRedaction.optionalDigest(settings.logFolderPath)),
                DiagnosticField("why", result.lastError?.diagnosticSummary ?? "-"),
            ])
            // REQ-ERR-004: 3回失敗した時点で通知する。
            if result.shouldNotify {
                notifications.notifyLogWriteFailure()
            }
        } catch {
            // **黙って失敗しない。**
            // Only bookmark resolution and starting access land here (VaultFileAccess).
            // REQ-ERR-010 / Decision 0034: keep the domain and the code, never the OS text.
            logWriteFailed = true
            let failure = error as? VaultFileAccess.AccessError
            lastLogError = failure?.displayMessage
                ?? "The session log could not be written. Check the folder set in Settings; unwritten entries stay queued."
            diagnostics.write("log.write", level: .error, [
                DiagnosticField("written", 0),
                DiagnosticField("pending", logQueue.pendingCount),
                DiagnosticField("why", failure?.diagnosticSummary ?? ErrorCode(error).summary("unexpected")),
            ])
        }
    }

    // MARK: - タスク

    func reloadTasksFromDisk() {
        guard let bookmark = bookmarks.taskFile else { return }
        // REQ-ERR-002: 失敗しても直前に成功した一覧を保持する。空リストで上書きしない。
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
        // 件数だけを残す。
        diagnostics.write("task.reload", level: outcome.context.loadFailed ? .warn : .info, [
            DiagnosticField("count", outcome.context.items.count),
            DiagnosticField("failed", outcome.context.loadFailed),
            DiagnosticField("truncated", outcome.context.wasTruncated),
            DiagnosticField("followed", outcome.didFollow),
            DiagnosticField("file", DiagnosticRedaction.optionalDigest(settings.taskFilePath)),
        ])
        persist()
        // REQ-TSK-002: 変更を検知したら iPhone へ最新リストを配信する。
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

    // MARK: - ファイル監視

    private func startWatchingTaskFile() {
        stopWatchingTaskFile()
        guard let bookmark = bookmarks.taskFile,
              let url = try? VaultFileAccess.beginAccess(to: bookmark) else { return }
        watchedTaskURL = url

        // REQ-TSK-002 / REQ-PLT-006: 親ディレクトリを 300ms デバウンスで監視する。
        let watcher = FileWatcher(fileURL: url) { [weak self] in
            Task { @MainActor in self?.reloadTasksFromDisk() }
        }
        try? watcher.start()
        self.watcher = watcher
    }

    private func stopWatchingTaskFile() {
        watcher?.stop()
        watcher = nil
        // REQ-PLT-005: start と stop を対にする。
        if let watchedTaskURL {
            VaultFileAccess.endAccess(to: watchedTaskURL)
            self.watchedTaskURL = nil
        }
    }

    // MARK: - ファイル選択

    func setTaskFile(_ url: URL) {
        // REQ-PLT-003: 読み取り専用として生成し、OS レベルで書き込みを不可能にする。
        guard let data = try? VaultFileAccess.readOnlyBookmark(for: url) else { return }
        bookmarks.taskFile = data
        bookmarks.save()
        settings.taskFilePath = url.path
    }

    // Decision 0015: 出力先は**フォルダ**。原子的書き込み (REQ-LOG-004 / REQ-PLT-004) には
    // 一時ファイルを作る許可が要る。
    func setLogFolder(_ url: URL) throws {
        // REQ-LOG-021: Task.md と同一のファイルは選べない。
        let taskURL = bookmarks.taskFile.flatMap { try? VaultFileAccess.resolve($0).url }
        let candidate = url.appendingPathComponent(settings.logFileName)
        try LogWriter.validate(logFileURL: candidate, taskFileURL: taskURL)

        guard let data = try? VaultFileAccess.readWriteBookmark(for: url) else {
            throw VaultFileAccess.AccessError.bookmarkCreationFailed
        }
        bookmarks.logFolder = data
        bookmarks.save()
        settings.logFolderPath = url.path
        // REQ-LOG-005: 溜まっていたぶんをここで書き出す。
        flushLogQueue()
    }

    // MARK: - 永続化

    // REQ-PER-001: 状態が変化するたびに永続化する。
    // REQ-ERR-017 / Decision 0035: 書けなかったことは、書けるようになるまで画面に出し続ける。
    private func persist() {
        // Decision 0036: 退避できなかったファイルの上には、一度も書かない。
        // **読めないことと、消してよいことは別である。** 止まっていることは status 行が言い続ける。
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
            // REQ-ERR-010 / Decision 0034: 画面には文、ログにはコード。
            let failure = (error as? StateStoreError) ?? .ioFailed(ErrorCode(error))
            lastSaveFailure = failure
            diagnostics.write("state.save", level: .error, [
                DiagnosticField("why", failure.diagnosticSummary),
            ])
        }
    }
}
