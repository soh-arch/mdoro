import Testing
import Foundation
import MdoroCore
@testable import MdoroMac

// REQ-ERR-010 / Decision 0018 / 0034: what `AppModel` actually writes to the diagnostic log.
//
// `MdoroCore` owns the format and holds it under `swift test`; what it cannot reach is the
// call sites, which live in this target. That gap was real — POL-034 found that
// `preset.notificationSound.diagnosticValue` could be changed back to `.rawValue` in two
// places and every test in the repository would still pass. So these read the file back
// rather than the fields handed in, which is the only version a reader on an issue sees.
//
// **利用者の資産に触れないこと。** ブックマークは空を渡す（Vault にもログにも書けない）、
// 診断ログは一時ディレクトリへ向ける、状態はメモリに置く。
// 既定のままだと、テストがホストアプリの本番の保存先へ書きに行く。

// 1行1イベント: `timestamp LEVEL code key=value ...`。
private struct LoggedEvent {
    let level: String
    let code: String
    let fields: [String: String]

    init?(_ line: String) {
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count >= 3, !line.hasPrefix("#") else { return nil }
        level = parts[1]
        code = parts[2]
        fields = parts.dropFirst(3).reduce(into: [:]) { result, part in
            guard let separator = part.firstIndex(of: "=") else { return }
            result[String(part[part.startIndex..<separator])] = String(part[part.index(after: separator)...])
        }
    }
}

// Decision 0034: `case(domain:code)` と、それ以外を受け付けない。
private func hasDiagnosticShape(_ value: String) -> Bool {
    guard let open = value.firstIndex(of: "("), value.hasSuffix(")") else { return false }
    let caseName = value[value.startIndex..<open]
    let inside = value[value.index(after: open)..<value.index(before: value.endIndex)]
    let parts = inside.split(separator: ":", maxSplits: 1)
    guard parts.count == 2, !caseName.isEmpty else { return false }
    return caseName.allSatisfy(\.isLetter)
        && !parts[0].isEmpty && parts[0].allSatisfy { $0.isLetter || $0 == "." }
        && Int(parts[1]) != nil
}

private struct Recording {
    let directory: URL
    let text: String
    let events: [LoggedEvent]
    // POL-047: what the app asked the notification centre for, had one been there.
    let notifications: [RecordedNotifications.Call]

    func events(_ code: String) -> [LoggedEvent] { events.filter { $0.code == code } }
}

@MainActor
private func record(
    preset: Preset,
    settings: AppSettings = AppSettings(),
    _ body: (AppModel) -> Void
) throws -> Recording {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("MdoroMacDiagnostics-\(UUID().uuidString)", isDirectory: true)

    let saved = PersistedState(
        timer: .idle(now: Date(), settings: settings),
        presets: PresetContext(presets: [preset], activePresetId: preset.id),
        settings: settings,
        savedAt: Date()
    )
    // POL-047: 通知も受け口を差し替える。**この的は利用者の通知センターである。**
    // これらのテストが読むのは診断ログであって通知ではない。
    let notifications = RecordedNotifications()
    let model = AppModel(
        store: InMemoryStateStore(initial: saved),
        diagnostics: DiagnosticLog(directory: directory),
        // 空のブックマーク。ログの書き込みは `log.blocked` で止まり、利用者のフォルダに届かない。
        bookmarks: VaultBookmarks(),
        notifications: notifications
    )
    model.diagnostics.open(preset: preset, settings: settings)
    body(model)

    let text = try String(
        contentsOf: directory.appendingPathComponent(DiagnosticLogFormat.currentFileName),
        encoding: .utf8
    )
    // 読み終わったら片付ける。判定はここから先、text に対して行う。
    try? FileManager.default.removeItem(at: directory)
    return Recording(
        directory: directory,
        text: text,
        events: text.split(separator: "\n").compactMap { LoggedEvent(String($0)) },
        notifications: notifications.calls
    )
}

// 終わったセッションを1つ作る。`send` は実時刻で `sessionEndAt` を置くので、
// 終了はそこを跨いだ `tick` で起こす。
@MainActor
private func runOneSessionToItsEnd(_ model: AppModel, taskSnapshot: String) {
    model.send(.startWork(presetId: model.presets.activePresetId, taskSnapshot: taskSnapshot))
    let endAt = model.timer.sessionEndAt ?? Date()
    model.tick(now: endAt.addingTimeInterval(1))
}

@Suite("What the Mac writes to the diagnostic log (REQ-ERR-010 / Decision 0018 / 0034)")
@MainActor
struct DiagnosticLogTests {

    // POL-047: this suite runs inside MdoroMac.app, so every notification it asked for was
    // delivered to the person at the machine — two at a time, once per case below. The
    // requests still have to be made, because what these tests read is the record the app
    // writes of having made them. Only the destination changed.
    @Test func theRequestsAreStillMadeAndNoneOfThemLeaveTheProcess() throws {
        var preset = Preset.standard()
        preset.notificationSound = .chime

        let recording = try record(preset: preset) { model in
            model.sendNotificationSoundTest(preset)
            runOneSessionToItsEnd(model, taskSnapshot: "task")
        }

        // 診断ログは今までどおり書かれる。
        #expect(recording.events("notify.test").count == 1)
        #expect(recording.events("notify.finished").count == 1)
        // そして配信はここで止まっている。
        #expect(recording.notifications.contains(.soundTest(.chime)))
        #expect(recording.notifications.contains(.sessionFinished(.work)))
        #expect(recording.notifications.filter { $0 == .soundTest(.chime) }.count == 1)
    }

    // Decision 0018: 読み手は issue を開いた第三者で、`chime` が何の音かを引く表がない。
    // 名前を落として raw value だけにすると、行は通るが読めなくなる。
    @Test func aSoundIsWrittenWithTheNameTheSettingsScreenShows() throws {
        var preset = Preset.standard()
        preset.notificationSound = .chime

        let recording = try record(preset: preset) { model in
            model.sendNotificationSoundTest(preset)
            runOneSessionToItsEnd(model, taskSnapshot: "task")
        }

        let test = try #require(recording.events("notify.test").first)
        let finished = try #require(recording.events("notify.finished").first)
        // `chime` だけでも `sound=chime(Glass)` に含まれてしまうので、値そのものを見る。
        #expect(test.fields["sound"] == "chime(Glass)")
        #expect(finished.fields["sound"] == "chime(Glass)")
        #expect(test.fields["sound"] != NotificationSound.chime.rawValue)
        // 先頭のヘッダも同じ値を持つ（Decision 0018 の環境ヘッダ）。
        #expect(recording.text.contains("sound=chime(Glass)"))
    }

    // 音は5つあり、そのうち2つは raw value と表示名が同じなので、1つだけ見ても差が出ない。
    @Test func everySoundIsWrittenTheSameWay() throws {
        for sound in NotificationSound.allCases {
            var preset = Preset.standard()
            preset.notificationSound = sound
            let recording = try record(preset: preset) { $0.sendNotificationSoundTest(preset) }
            let test = try #require(recording.events("notify.test").first)
            #expect(test.fields["sound"] == sound.diagnosticValue)
        }
    }

    // Decision 0034: `why` は、誰が投げた失敗でも `case(domain:code)`。
    @Test func everyReasonIsWrittenAsADomainAndACode() throws {
        let recording = try record(preset: Preset.standard()) { model in
            // IDLE では延長できない。拒否された操作は記録される。
            model.send(.extend)
            // 終わったセッションを確定させると、書き込み先が無いことが分かる。
            runOneSessionToItsEnd(model, taskSnapshot: "task")
            model.send(.startWork(presetId: model.presets.activePresetId, taskSnapshot: "task"))
        }

        let reasons = recording.events.compactMap { $0.fields["why"] }.filter { $0 != "-" }
        #expect(!reasons.isEmpty, "`why` を持つ行が1つも出ていない。テストが何も確かめていない")
        for reason in reasons {
            #expect(hasDiagnosticShape(reason), "not `case(domain:code)`: \(reason)")
        }

        let rejected = try #require(recording.events("action.rejected").first)
        #expect(rejected.fields["why"] == TimerError.invalidStateForAction.diagnosticSummary)
        let blocked = try #require(recording.events("log.blocked").first)
        #expect(blocked.fields["why"] == ErrorCode.logFolderNotSet.summary("noFolder"))
    }

    // REQ-ERR-010 / Decision 0018: **書き出すときに伏せるのではなく、載せない。**
    // タスク名・パス・ファイル名・ホスト名を与えたうえで、ファイル全体を見る。
    @Test func nothingTheUserWroteReachesTheFile() throws {
        let taskName = "REVIEWTHEQUARTERLYPLAN"
        let vaultPath = "/Users/someone/Vault/UNIQUETASKFILE.md"
        let logFolder = "/Users/someone/Vault/UNIQUELOGFOLDER"
        let logFileName = "UNIQUELOGNAME.md"
        let presetName = "UNIQUEPRESETNAME"
        let hostName = ProcessInfo.processInfo.hostName

        var preset = Preset.standard()
        preset.name = presetName
        let settings = AppSettings(
            taskFilePath: vaultPath, logFolderPath: logFolder, logFileName: logFileName
        )

        let recording = try record(preset: preset, settings: settings) { model in
            runOneSessionToItsEnd(model, taskSnapshot: taskName)
            model.send(.startWork(presetId: model.presets.activePresetId, taskSnapshot: taskName))
            model.reloadTasksFromDisk()
            // 設定が変わった行も出させる。ここが `vault=` `logDir=` を書く経路。
            model.settings.logicalDayStartHour = 5
            model.stop()
        }

        for secret in [taskName, vaultPath, logFolder, logFileName, presetName, hostName] {
            #expect(
                !recording.text.contains(secret),
                "REQ-ERR-010: `\(secret)` が診断ログに出ている"
            )
        }
        // パスは載せないが、同じ設定を使い続けているかは追える（Decision 0018）。
        #expect(recording.text.contains("vault=\(DiagnosticRedaction.digest(vaultPath))"))
        // 走査が空のファイルを見ていないこと。
        #expect(recording.events.count > 3, "行が少なすぎる。上の禁止語検査は何も見ていない")
    }

    // 選ばれているタスクがあることは記録するが、それが何かは記録しない。
    @Test func aSelectedTaskIsCountedNotNamed() throws {
        let recording = try record(preset: Preset.standard()) { model in
            model.send(.startWork(presetId: model.presets.activePresetId, taskSnapshot: "SOMETASKNAME"))
        }
        let action = try #require(recording.events("action").first)
        #expect(action.fields["task"] == "set")
        #expect(action.fields["do"] == "startWork")
    }
}
