#if os(iOS)
import AppIntents

// REQ-UIX-024: `perform()` は**アプリ本体のプロセス**で実行される。
// その中で Mac へのコマンド送信を試み、**失敗したら状態を変更したかのように見せない。**
//
// アプリ本体のターゲットに置くのはそのため。拡張側に置くとネットワークに触れない（REQ-UIX-026）。
@MainActor
public enum LiveActivityCommandBridge {
    // アプリが動いていれば、起動中の ClientModel がここに自分を差し込む。
    public static var handler: ((CommandAction) -> Bool)?

    // 送れたかどうかを返す。送れなかったことを握り潰さない。
    public static func send(_ action: CommandAction) -> Bool {
        handler?(action) ?? false
    }
}

public struct PauseSessionIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Pause"
    public static let isDiscoverable: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        _ = await MainActor.run { LiveActivityCommandBridge.send(.pause) }
        // 送れなかった場合でも「一時停止した」とは見せない。
        // Live Activity は次の更新が来るまで従来の表示のままで、やがて isStale へ移る（REQ-UIX-023）。
        return .result()
    }
}

public struct ResumeSessionIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Resume"
    public static let isDiscoverable: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        _ = await MainActor.run { LiveActivityCommandBridge.send(.resume) }
        return .result()
    }
}

#endif
