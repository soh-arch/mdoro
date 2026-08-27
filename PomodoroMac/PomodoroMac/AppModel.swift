import Foundation
import SwiftUI
import Observation
import PomodoroCore

// Mac 側の状態保持と、PomodoroCore への配線。
//
// **状態の正本は Mac である**（3原則の2つ目）。判断はすべて `TimerEngine` が行い、
// ここはその結果を受け取って副作用（ログ書き込み・通知・永続化）を実行する係に徹する。
// ドメインの判断をこのクラスに書かないこと。
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

    // 表示用の現在時刻。**ビュー側に Timer を持たせない。**
    // ビューに Timer.publish を置いたところ発火せず、メインウィンドウの残り時間が固まった。
    private(set) var displayNow = Date()

    // REQ-UIX-004 / 035: 接続状態。実際の接続管理は工程5（第3章・第12章）が入れる。
    // それまでは iPhone が繋がることはないので、正直に「未接続」を出す。
    private(set) var connection: ConnectionStatus = .disconnected
    // REQ-UIX-033: 割り当ててあるのに他アプリに取られている場合を UI で区別する。
    private(set) var pauseResumeHotKeyIsActive = false
    private(set) var showWindowHotKeyIsActive = false
    // REQ-SEC-001: ペアリング中に Mac 画面へ表示する6桁コード。
    private(set) var pairingCode: String?
    private(set) var pairingRemainingSeconds = 0
    // REQ-SEC-004: 別のクライアントからの接続要求。ユーザーの承認を待つ。
    private(set) var pendingConnectionRequest: String?
    private(set) var serverStartError: String?

    // REQ-ERR-004 / REQ-LOG-005: 書き込みに失敗し続けていることを UI に出す。
    private(set) var logWriteFailed = false
    // REQ-ERR-004: 失敗の理由を UI に出す。原因が分からないまま記録だけ消えるのが最悪。
    private(set) var lastLogError: String?
    // 書けていない件数。0 でないまま放置されると記録が失われる。
    private(set) var pendingLogCount = 0
    // 直近に書き込めた時刻。書けているのかどうかを UI から確かめられるようにする。
    private(set) var lastLogWriteAt: Date?
    // 直近の再読み込みで選択が自動追従したこと（REQ-TSK-032）を控えめに知らせる。
    private(set) var didFollowTaskSelection = false

    // MARK: - 依存

    private let store: any StateStore
    private let notifications = NotificationScheduler()
    private let idleSleepGuard = IdleSleepGuard()
    private let hotKeys = HotKeyCenter()
    private let server = PomodoroServer()
    // REQ-ERR-010 / Decision 0018: タスク名もパスも載せない診断ログ。
    let diagnostics = DiagnosticLog()
    private var infoServer: InfoHTTPServer?
    private var authenticator = Authenticator(issuedTokens: DeviceTokenStore.load())
    private let logQueue: LogWriteQueue
    private var bookmarks = VaultBookmarks.load()

    private var watcher: FileWatcher?
    private var watchedTaskURL: URL?
    private var tickTask: Task<Void, Never>?

    // MARK: - 生成

    init(store: any StateStore, now: Date = Date()) {
        self.store = store
        let restored = (try? store.loadAndRestore(now: now))
        let saved = try? store.load()

        self.timer = restored?.context ?? .idle(now: now)
        self.presets = restored?.presets ?? .initial()
        self.settings = saved?.settings ?? .default
        self.tasks = TaskContext(
            selectedTaskId: saved?.selectedTaskId,
            selectedTaskSnapshot: saved?.selectedTaskSnapshot
        )
        // REQ-LOG-005: 書き込めていないログを引き継ぐ。committedAt は既に立っているため、
        // ここで捨てると、そのセッションの記録は二度と書かれない。
        self.logQueue = LogWriteQueue(entries: saved?.pendingLogEntries ?? [])
        self.pendingLogCount = self.logQueue.pendingCount

        // REQ-PER-003(d): 復元で判断待ちになった場合、通知の取り消しなどの副作用も実行する。
        apply(effects: restored?.effects ?? [])
        persist()
    }

    convenience init() {
        let store: any StateStore = (try? FileStateStore.inApplicationSupport()) ?? InMemoryStateStore()
        self.init(store: store)
    }

    // MARK: - ライフサイクル

    func start() {
        diagnostics.open(preset: presets.activePreset ?? Preset.standard(), settings: settings)
        diagnostics.write("app.start")
        Task { await notifications.requestAuthorization() }
        // 前回書けなかったぶんを、出力先が使えるなら真っ先に書き出す。
        flushLogQueue()
        reloadTasksFromDisk()
        startWatchingTaskFile()
        startTicking()
        syncSideEffectsToState()
        updateHotKey()
        Task { await startServer() }
    }

    // REQ-TIM-001: 表示のためのカウントダウンであって、時間の正本ではない。
    // 残り時間は毎回 `sessionEndAt` から算出する（3原則の3つ目）。
    // 1秒ちょうどで回すと、Task.sleep のずれが積もって表示が1秒飛ぶことがある。
    // 表示の粒度より細かく回し、秒の切り替わりを取りこぼさないようにする。
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

    private func tick() {
        let now = Date()
        // 残り時間の表示はここで進める。状態が変わらなくても毎秒更新する。
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
            notifications.notifySessionFinished(
                type: previousType,
                nextType: timer.nextSessionType,
                taskName: timer.sessionTaskSnapshot,
                preset: presets.activePreset ?? Preset.standard()
            )
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
        // 操作した瞬間の時刻で描き直す。次の tick まで古い時刻のままだと、
        // 開始直後に「25:01」のように長さより大きい値が出る。
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
            // 拒否された操作こそ記録する。「押したのに何も起きない」を後から追える。
            diagnostics.write("action.rejected", level: .warn, [
                DiagnosticField("do", action.diagnosticName),
                DiagnosticField("state", timer.runState.rawValue),
                DiagnosticField("why", String(describing: failure.error)),
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

    // 状態に応じて、外の世界を合わせる。
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
        // ヘッダは開いたときの値なので、変わったら現在値を1行残す。
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
            || settings.showWindowHotKey != previous.showWindowHotKey {
            updateHotKey()
        }
        if settings.launchAtLogin != previous.launchAtLogin {
            // 失敗したら設定を元に戻す。UI が実態と食い違わないようにする。
            if !LoginItem.setEnabled(settings.launchAtLogin) {
                settings.launchAtLogin = previous.launchAtLogin
            }
        }
        persist()
    }

    // REQ-UIX-033: 「一時停止 / 再開」だけをグローバルに割り当てる。
    // 中断・リセットは誤爆すると取り返しがつかないので、メインウィンドウに留める（REQ-UIX-031 と同じ理由）。
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
        pauseResumeHotKeyIsActive = hotKeys.isRegistered(.pauseResume)
        showWindowHotKeyIsActive = hotKeys.isRegistered(.showWindow)
    }

    // ウィンドウを前面に出す処理は Scene 側が握っているため、呼び出し口だけ持つ。
    var onShowWindowRequested: (() -> Void)?

    // MARK: - 通信 (第3章 / 第10章)

    private func startServer() async {
        do {
            let websocketPort = try await server.start(callbacks: serverCallbacks())
            // REQ-COM-002 / 003: Bonjour で広告し、`GET /info` でサーバー情報を返す。
            let info = InfoHTTPServer(info: serverInfo(websocketPort: websocketPort))
            try await info.start()
            info.advertise(serviceName: Host.current().localizedName ?? "Pomodoro", websocketPort: websocketPort)
            infoServer = info
            websocketPortForInfo = websocketPort
            serverStartError = nil
        } catch {
            // REQ-SEC-005 / REQ-ERR-008: 待ち受けられない事実を隠さない。
            serverStartError = String(describing: error)
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

    // ペアリングの開始・終了で `/info` の内容が変わる。押し込み忘れると、
    // iPhone 側が「ペアリング中かどうか」を誤って表示する。
    private func refreshServerInfo() {
        infoServer?.update(serverInfo(websocketPort: websocketPortForInfo))
    }

    private func serverCallbacks() -> PomodoroServer.Callbacks {
        PomodoroServer.Callbacks(
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
                // 端末名も IP も書かない。繋がったかどうかだけが要る。
                diagnostics.write("conn", [DiagnosticField("up", state.isConnected)])
            }
        )
    }

    // 受け取ったコマンドは翻訳して状態機械へ渡す。可否は状態機械が決める（REQ-ERR-016）。
    private func apply(_ command: CommandPayload) {
        // タスクと設定は状態機械の管轄外（`TimerEngine` は break するだけ）。
        // ここで受け止めないと、iPhone からの選択が**黙って捨てられる**。
        switch command.action {
        case .selectTask:
            guard let stableId = command.params?.stableId else {
                reject(.invalidStateForAction, "stableId がありません", command)
                return
            }
            // REQ-TSK-036: 現在の一覧に存在しない stableId は受け付けず、選択も変えない。
            guard tasks.item(id: stableId) != nil else {
                reject(.taskNotFound, "そのタスクは見つかりません", command)
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
                reject(.invalidStateForAction, "settings がありません", command)
                return
            }
            // didSet が検証・永続化・状態機械への反映をまとめて行う。
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
            if let error = send(action) {
                server.broadcast(.error(ProtocolErrorPayload(
                    code: ProtocolErrorCode(error),
                    message: String(describing: error),
                    relatedRequestId: command.clientRequestId
                )))
            }
        case let .failure(failure):
            server.broadcast(.error(ProtocolErrorPayload(
                code: failure.errorCode,
                message: String(describing: failure),
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
            parseError: tasks.loadFailed ? "Task.md を読み込めませんでした" : nil
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

    // REQ-SEC-004: ユーザーが承認した場合のみ既存接続を切断して新接続を受け入れる。
    // 60秒で自動的にタイムアウトし、既定は拒否（サーバー側が計る）。
    func respondToConnectionRequest(approved: Bool) {
        pendingConnectionRequest = nil
        // 承認するなら、認証器の「接続中」を先に空けておく。
        // ここを空けないと、再認証がまた needsUserApproval を返して堂々巡りになる。
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
            // 出力先が未設定でも記録は捨てず、キューへ残す。設定された時点で書き出す。
            logWriteFailed = true
            lastLogError = "実績ログの出力先が設定されていません"
            diagnostics.write("log.blocked", level: .warn, [
                DiagnosticField("why", "noFolder"),
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
            lastLogError = result.lastError.map { String(describing: $0) }
            // Vault へ何を書いたかは残す。**書いたことの証拠になる。**
            diagnostics.write("log.write", level: result.pending > 0 ? .warn : .info, [
                DiagnosticField("written", result.written),
                DiagnosticField("pending", result.pending),
                DiagnosticField("file", DiagnosticRedaction.optionalDigest(settings.logFolderPath)),
                DiagnosticField("why", result.lastError.map { String(describing: $0) } ?? "-"),
            ])
            // REQ-ERR-004: 3回失敗した時点で通知する。
            if result.shouldNotify {
                notifications.notifyLogWriteFailure()
            }
        } catch {
            // **黙って失敗しない。** ここを握り潰すと、記録が残らないことに誰も気づけない。
            logWriteFailed = true
            lastLogError = String(describing: error)
            diagnostics.write("log.write", level: .error, [
                DiagnosticField("written", 0),
                DiagnosticField("pending", logQueue.pendingCount),
                DiagnosticField("why", String(describing: error)),
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
        // 件数だけを残す。タスク名も見出しも書かない。
        diagnostics.write("task.reload", level: outcome.context.loadFailed ? .warn : .info, [
            DiagnosticField("count", outcome.context.items.count),
            DiagnosticField("failed", outcome.context.loadFailed),
            DiagnosticField("truncated", outcome.context.wasTruncated),
            DiagnosticField("followed", outcome.didFollow),
            DiagnosticField("file", DiagnosticRedaction.optionalDigest(settings.taskFilePath)),
        ])
        persist()
        // REQ-TSK-002: 変更を検知したら iPhone へ最新リストを配信する。
        // ここを忘れると、Mac 側で Task.md を編集しても iPhone は古い一覧のままになる。
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
        // REQ-PLT-003: 読み取り専用として生成する。OS レベルで書き込みを不可能にする。
        guard let data = try? VaultFileAccess.readOnlyBookmark(for: url) else { return }
        bookmarks.taskFile = data
        bookmarks.save()
        settings.taskFilePath = url.path
    }

    // Decision 0015: 出力先は**フォルダ**を選ばせる。
    // 一時ファイル経由の原子的書き込み (REQ-LOG-004 / REQ-PLT-004) には、
    // ログ本体だけでなく**同じフォルダへの書き込み許可**が要る。
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
        // 失敗して溜まっていたぶんがあれば、ここで書き出す (REQ-LOG-005)。
        flushLogQueue()
    }

    // MARK: - 永続化

    // REQ-PER-001: 状態が変化するたびに永続化する。
    private func persist() {
        try? store.save(
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
    }
}
