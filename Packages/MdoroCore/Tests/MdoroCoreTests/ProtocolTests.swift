import Testing
import Foundation
@testable import MdoroCore

private let now = Date(timeIntervalSince1970: 1_700_000_000)

@Suite("Message encoding (REQ-PRT-002 / 005 / 006)")
struct MessageCodingTests {

    // REQ-PRT-002: type / messageId / sentAt は必須。
    @Test func everyMessageCarriesTheRequiredHeader() throws {
        let envelope = Envelope(body: ClientMessage.heartbeat)
        let data = try MessageCoder.encode(envelope)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "heartbeat")
        #expect(object["messageId"] as? String == envelope.header.messageId)
        #expect(object["sentAt"] != nil)
    }

    @Test func clientMessagesRoundTrip() throws {
        let messages: [ClientMessage] = [
            .hello(HelloPayload(deviceToken: "tok", deviceName: "iPhone")),
            .timeSyncPing(TimeSyncPayload(t1: now)),
            .heartbeat,
            .command(CommandPayload(clientRequestId: "r1", action: .startBreak,
                                    params: CommandParams(sessionType: .shortBreak))),
            .requestSnapshot,
        ]
        for message in messages {
            let data = try MessageCoder.encode(Envelope(body: message))
            let decoded = try #require(try MessageCoder.decodeClient(data))
            #expect(decoded.body == message)
        }
    }

    @Test func serverMessagesRoundTrip() throws {
        let snapshot = StateSnapshot(
            timer: .idle(now: now), task: TaskContext(), settings: .default,
            presets: .initial(), connection: ConnectionState(isConnected: true, peerDeviceName: "Mac")
        )
        let messages: [ServerMessage] = [
            .welcome(WelcomePayload(deviceToken: "tok", serverName: "Mac")),
            .authFailed(AuthFailedPayload(code: .invalidPairingCode, message: "違います")),
            .timeSyncPong(TimeSyncPayload(t1: now, t2: now, t3: now)),
            .stateSnapshot(snapshot),
            .sessionEvent(SessionEventPayload(event: .reachedEnd, sessionType: .work,
                                              loopCount: 1, nextSessionType: .shortBreak)),
            .error(ProtocolErrorPayload(code: .extendWindowClosed, message: "窓の外", relatedRequestId: "r1")),
        ]
        for message in messages {
            let data = try MessageCoder.encode(Envelope(body: message))
            let decoded = try #require(try MessageCoder.decodeServer(data))
            #expect(decoded.body == message)
        }
    }

    // REQ-PRT-005: 未知の**種別**は無視する。例外にすると、
    // 将来のバージョンがメッセージを1つ足しただけで接続が落ちる。
    @Test func unknownMessageTypeIsIgnoredNotAnError() throws {
        let json = #"{"type":"somethingNew","messageId":"m1","sentAt":"2023-11-14T22:13:20Z"}"#
        #expect(try MessageCoder.decodeClient(Data(json.utf8)) == nil)
        #expect(try MessageCoder.decodeServer(Data(json.utf8)) == nil)
    }

    // REQ-PRT-005: 未知の**フィールド**も無視する。
    @Test func unknownFieldsAreIgnored() throws {
        let json = """
        {"type":"hello","messageId":"m1","sentAt":"2023-11-14T22:13:20Z",
         "protocolVersion":1,"deviceName":"iPhone","futureField":{"a":1}}
        """
        let decoded = try #require(try MessageCoder.decodeClient(Data(json.utf8)))
        guard case let .hello(payload) = decoded.body else {
            Issue.record("hello として解釈されるべき")
            return
        }
        #expect(payload.deviceName == "iPhone")
    }

    // REQ-PRT-006: 時間を表すフィールドは秒単位の整数。
    @Test func durationsAreEncodedAsWholeSeconds() throws {
        let data = try MessageCoder.encoder.encode(Preset.standard(id: "p"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["workSeconds"] as? Int == 1500)
        #expect(object["extendSeconds"] as? Int == 300)
    }

    // REQ-PRT-004: 非互換なバージョンは受け付けない。
    @Test func protocolVersionCompatibility() {
        #expect(PomodoroProtocol.isCompatible(PomodoroProtocol.version))
        #expect(!PomodoroProtocol.isCompatible(PomodoroProtocol.version + 1))
    }
}

@Suite("Time sync (REQ-COM-007 / 008 / 009)")
struct TimeSyncTests {

    // REQ-COM-008 の式そのもの。
    @Test func offsetAndRoundTripUseTheSpecifiedFormula() {
        // サーバーが 10 秒進んでいて、往復 200ms（片道 100ms）の場合。
        let t1 = now
        let t2 = now.addingTimeInterval(10.1)
        let t3 = now.addingTimeInterval(10.1)
        let t4 = now.addingTimeInterval(0.2)
        let sample = TimeSyncSample(t1: t1, t2: t2, t3: t3, t4: t4)
        #expect(abs(sample.offset - 10.0) < 0.0001)
        #expect(abs(sample.roundTrip - 0.2) < 0.0001)
    }

    // REQ-COM-008: 往復遅延 500ms 超は棄却する。
    @Test func slowSamplesAreRejected() {
        var estimator = TimeSyncEstimator()
        estimator.add(TimeSyncSample(offset: 99, roundTrip: 0.6))
        #expect(estimator.sampleCount == 0)
        estimator.add(TimeSyncSample(offset: 1, roundTrip: 0.5))
        #expect(estimator.sampleCount == 1)
    }

    // 3件未満は最小往復遅延のサンプルをそのまま使う。
    @Test func fewSamplesUseTheFastestRoundTrip() {
        var estimator = TimeSyncEstimator()
        estimator.add(TimeSyncSample(offset: 5, roundTrip: 0.4))
        estimator.add(TimeSyncSample(offset: 1, roundTrip: 0.05))
        #expect(estimator.offset == 1, "the sample with the fastest round trip must be used")
    }

    // 3件以上は直近7件の中央値。外れ値に引きずられない。
    @Test func medianOfTheLastSevenSamples() {
        var estimator = TimeSyncEstimator()
        for offset in [1.0, 1.1, 50.0, 1.2, 1.05] {
            estimator.add(TimeSyncSample(offset: offset, roundTrip: 0.1))
        }
        #expect(estimator.offset == 1.1, "the outlier 50 must not drag the median")
    }

    @Test func windowKeepsOnlyTheLastSeven() {
        var estimator = TimeSyncEstimator()
        for i in 0..<20 {
            estimator.add(TimeSyncSample(offset: Double(i), roundTrip: 0.1))
        }
        #expect(estimator.sampleCount == TimeSyncEstimator.windowSize)
        #expect(estimator.offset == 16, "the median of 13...19")
    }

    // REQ-COM-009: サーバー時刻を自端末の時計へ直す。
    @Test func serverTimeIsConvertedToLocalTime() {
        var estimator = TimeSyncEstimator()
        for _ in 0..<3 { estimator.add(TimeSyncSample(offset: 10, roundTrip: 0.1)) }
        let serverEnd = now.addingTimeInterval(1500)
        #expect(estimator.localTime(forServerTime: serverEnd) == serverEnd.addingTimeInterval(-10))
    }

    // REQ-ERR-007: 5 秒を超えたら補正で押し込めず警告する。
    @Test func largeOffsetRaisesAWarning() {
        var estimator = TimeSyncEstimator()
        for _ in 0..<3 { estimator.add(TimeSyncSample(offset: 6, roundTrip: 0.1)) }
        #expect(estimator.needsClockWarning)

        var small = TimeSyncEstimator()
        for _ in 0..<3 { small.add(TimeSyncSample(offset: 1, roundTrip: 0.1)) }
        #expect(!small.needsClockWarning)
    }
}

@Suite("Reconnect and heartbeat (REQ-COM-004 / 005)")
struct ReconnectTests {

    // REQ-COM-004: 初回1秒、上限30秒の指数バックオフ。
    @Test func backoffDoublesUpToThirtySeconds() {
        var policy = ReconnectPolicy()
        #expect(policy.nextDelay() == 1)
        #expect(policy.nextDelay() == 2)
        #expect(policy.nextDelay() == 4)
        #expect(policy.nextDelay() == 8)
        #expect(policy.nextDelay() == 16)
        #expect(policy.nextDelay() == 30, "the backoff caps at 30 seconds")
        #expect(policy.nextDelay() == 30)
    }

    // 成功したら戻す。戻し忘れると、一度荒れた回線が延々と30秒待ちになる。
    @Test func successResetsTheBackoff() {
        var policy = ReconnectPolicy()
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        policy.reset()
        #expect(policy.nextDelay() == 1)
    }

    // REQ-COM-005: 15秒応答がなければ接続断とみなす。
    @Test func heartbeatTimesOutAfterFifteenSeconds() {
        #expect(Heartbeat.interval == 5)
        #expect(!Heartbeat.isStale(lastReceivedAt: now, now: now.addingTimeInterval(15)))
        #expect(Heartbeat.isStale(lastReceivedAt: now, now: now.addingTimeInterval(15.1)))
        #expect(Heartbeat.isStale(lastReceivedAt: nil, now: now))
    }
}
