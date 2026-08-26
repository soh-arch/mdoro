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

    // REQ-UIX-004 / 035: 接続状態。実際の接続管理は工程5（第3章・第12章）が入れる。
    // それまでは iPhone が繋がることはないので、正直に「未接続」を出す。
    private(set) var connection: ConnectionStatus = .disconnected

    // REQ-ERR-004 / REQ-LOG-005: 書き込みに失敗し続けていることを UI に出す。
    private(set) var logWriteFailed = false
    // 直近の再読み込みで選択が自動追従したこと（REQ-TSK-032）を控えめに知らせる。
    private(set) var didFollowTaskSelection = false

    // MARK: - 依存

    private let store: any StateStore
    private let notifications = NotificationScheduler()
    private let idleSleepGuard = IdleSleepGuard()
    private let logQueue = LogWriteQueue()
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
        Task { await notifications.requestAuthorization() }
        reloadTasksFromDisk()
        startWatchingTaskFile()
        startTicking()
        syncSideEffectsToState()
    }

    // REQ-TIM-001: 表示のためのカウントダウンであって、時間の正本ではない。
    // 残り時間は毎回 `sessionEndAt` から算出する（3原則の3つ目）。
    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.tick()
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        stopWatchingTaskFile()
        idleSleepGuard.end()
    }

    private func tick() {
        let now = Date()
        let previousState = timer.runState
        let previousType = timer.sessionType
        let result = TimerEngine.tick(context: timer, presets: presets, settings: settings, now: now)
        guard result.context != timer || !result.effects.isEmpty else { return }

        timer = result.context
        apply(effects: result.effects)

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

    // MARK: - 操作

    @discardableResult
    func send(_ action: TimerAction) -> TimerError? {
        let now = Date()
        switch TimerEngine.reduce(action: action, context: timer, presets: presets, settings: settings, now: now) {
        case let .success(reduction):
            timer = reduction.context
            presets = reduction.presets
            apply(effects: reduction.effects)
            syncSideEffectsToState()
            persist()
            return nil
        case let .failure(failure):
            // REQ-LOG-018: 拒否されても、直前の tick が確定させたログは失わない。
            apply(effects: failure.effects)
            persist()
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
            return
        }
        // REQ-PER-004: logicalDayStartHour の変更で PENDING_DECISION を自動確定させない。
        send(.updateSettings(settings))
        if settings.taskFilePath != previous.taskFilePath {
            reloadTasksFromDisk()
            startWatchingTaskFile()
        }
        persist()
    }

    // MARK: - ログ

    private func enqueueLog(_ entry: LogEntry) {
        logQueue.enqueue(entry)
        flushLogQueue()
    }

    func flushLogQueue() {
        guard let bookmark = bookmarks.logFile else { return }
        let options = LogFormatter.Options(taskAsLink: settings.logTaskAsLink)

        let result = try? VaultFileAccess.withAccess(to: bookmark) { logURL -> LogWriteQueue.FlushResult in
            // REQ-LOG-021 / 第1原則: Task.md を書き込み先にしない。書き込みのたびに確かめる。
            let taskURL = bookmarks.taskFile.flatMap { try? VaultFileAccess.resolve($0).url }
            let writer = LogWriter(fileURL: logURL, taskFileURL: taskURL, options: options)
            return logQueue.flush { try writer.append($0) }
        }

        guard let result else { return }
        logWriteFailed = result.pending > 0
        // REQ-ERR-004: 3回失敗した時点で通知する。
        if result.shouldNotify {
            notifications.notifyLogWriteFailure()
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
        persist()
    }

    func selectTask(id: String) {
        var updated = tasks
        guard (try? updated.select(id: id)) != nil else { return }
        tasks = updated
        send(.selectTask(snapshot: updated.selectedTaskSnapshot))
    }

    func clearTaskSelection() {
        tasks.clearSelection()
        send(.clearTaskSelection)
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

    // REQ-LOG-021: Task.md と同一のファイルは選べない。
    func setLogFile(_ url: URL) throws {
        let taskURL = bookmarks.taskFile.flatMap { try? VaultFileAccess.resolve($0).url }
        try LogWriter.validate(logFileURL: url, taskFileURL: taskURL)
        guard let data = try? VaultFileAccess.readWriteBookmark(for: url) else {
            throw VaultFileAccess.AccessError.bookmarkCreationFailed
        }
        bookmarks.logFile = data
        bookmarks.save()
        settings.logFilePath = url.path
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
                savedAt: Date()
            )
        )
    }
}
