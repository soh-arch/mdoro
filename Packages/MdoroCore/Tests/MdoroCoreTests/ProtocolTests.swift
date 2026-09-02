import Testing
import Foundation
@testable import MdoroCore

private let now = Date(timeIntervalSince1970: 1_700_000_000)

@Suite("Message encoding (REQ-PRT-002 / 005 / 006)")
struct MessageCodingTests {

    // REQ-PRT-002: type / messageId / sentAt are required.
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
            .authFailed(AuthFailedPayload(code: .invalidPairingCode)),
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

    // REQ-PRT-005: an unknown **type** is ignored. Raise instead, and a future version that adds
    // one message drops the connection.
    @Test func unknownMessageTypeIsIgnoredNotAnError() throws {
        let json = #"{"type":"somethingNew","messageId":"m1","sentAt":"2023-11-14T22:13:20Z"}"#
        #expect(try MessageCoder.decodeClient(Data(json.utf8)) == nil)
        #expect(try MessageCoder.decodeServer(Data(json.utf8)) == nil)
    }

    // REQ-PRT-005: an unknown **field** is ignored too.
    @Test func unknownFieldsAreIgnored() throws {
        let json = """
        {"type":"hello","messageId":"m1","sentAt":"2023-11-14T22:13:20Z",
         "protocolVersion":1,"deviceName":"iPhone","futureField":{"a":1}}
        """
        let decoded = try #require(try MessageCoder.decodeClient(Data(json.utf8)))
        guard case let .hello(payload) = decoded.body else {
            Issue.record("it was not interpreted as hello")
            return
        }
        #expect(payload.deviceName == "iPhone")
    }

    // REQ-PRT-005 / REQ-ERR-009: **a value this version does not know is a broken message, not a
    // forward-compatible one.**
    //
    // REQ-PRT-005 ignores an unknown *type* and an unknown *field*, and stops there. That first
    // half is a trade rather than a theorem: it puts "a later addition must not break an older
    // device" ahead of the danger it knowingly takes on — quietly throwing away something whose
    // meaning it cannot see. The clause declines to widen that trade to a value riding on a field
    // this version already knows.
    //
    // So the value is not bent onto the nearest known case: picking whichever refusal
    // `someFutureRefusal` resembles would put a sentence on the iPhone's screen that the Mac never
    // said. That leaves nothing to read the message as, and a message that cannot be read is
    // REQ-ERR-009's broken message — where an unknown type decodes to nil and is ignored, this
    // raises.
    //
    // Both ends discard the one message and keep the line; REQ-ERR-009 judges the line itself on
    // a run of ten.
    @Test func aValueThisVersionDoesNotKnowRaisesRatherThanDecodingToTheWrongCase() throws {
        let refusal = """
        {"type":"authFailed","messageId":"m1","sentAt":"2023-11-14T22:13:20Z",
         "code":"someFutureRefusal","message":"someFutureRefusal(Mdoro:99)"}
        """
        #expect(throws: DecodingError.self) {
            try MessageCoder.decodeServer(Data(refusal.utf8))
        }

        // The same shape in the other direction: an unknown value on a command's `action`.
        let command = """
        {"type":"command","messageId":"m2","sentAt":"2023-11-14T22:13:20Z",
         "clientRequestId":"r1","action":"someFutureAction"}
        """
        #expect(throws: DecodingError.self) {
            try MessageCoder.decodeClient(Data(command.utf8))
        }
    }

    // REQ-PRT-006: a field standing for a duration is a whole number of seconds.
    @Test func durationsAreEncodedAsWholeSeconds() throws {
        let data = try MessageCoder.encoder.encode(Preset.standard(id: "p"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["workSeconds"] as? Int == 1500)
        #expect(object["extendSeconds"] as? Int == 300)
    }

    // REQ-PRT-004: an incompatible version is not accepted.
    @Test func protocolVersionCompatibility() {
        #expect(PomodoroProtocol.isCompatible(PomodoroProtocol.version))
        #expect(!PomodoroProtocol.isCompatible(PomodoroProtocol.version + 1))
    }

    // REQ-PRT-004 / Decision 0040: **the number itself is what the clause asks for.**
    //
    // v2.25 changed what is in the TXT record and what the iPhone's Keychain key means, and
    // raising this is the whole mechanism that stops an old iPhone and a new Mac from half
    // working in silence. Every other test in the repository reads `PomodoroProtocol.version`
    // relatively, so putting it back to 1 left all of them green — the requirement was met by a
    // literal that nothing was holding down.
    @Test func theProtocolVersionIsTheOneDecision0040Raised() {
        #expect(
            PomodoroProtocol.version == 2,
            "REQ-PRT-004: v2.25 raised the protocol version; lowering it lets an old pairing half work"
        )
    }
}

@Suite("Time sync (REQ-COM-007 / 008 / 009)")
struct TimeSyncTests {

    // The formula of REQ-COM-008 itself.
    @Test func offsetAndRoundTripUseTheSpecifiedFormula() {
        // The server is 10 seconds ahead, with a 200ms round trip (100ms each way).
        let t1 = now
        let t2 = now.addingTimeInterval(10.1)
        let t3 = now.addingTimeInterval(10.1)
        let t4 = now.addingTimeInterval(0.2)
        let sample = TimeSyncSample(t1: t1, t2: t2, t3: t3, t4: t4)
        #expect(abs(sample.offset - 10.0) < 0.0001)
        #expect(abs(sample.roundTrip - 0.2) < 0.0001)
    }

    // REQ-COM-008: a round trip of more than 500ms is discarded.
    @Test func slowSamplesAreRejected() {
        var estimator = TimeSyncEstimator()
        estimator.add(TimeSyncSample(offset: 99, roundTrip: 0.6))
        #expect(estimator.sampleCount == 0)
        estimator.add(TimeSyncSample(offset: 1, roundTrip: 0.5))
        #expect(estimator.sampleCount == 1)
    }

    // Below three samples, the one with the smallest round trip is used as it is.
    @Test func fewSamplesUseTheFastestRoundTrip() {
        var estimator = TimeSyncEstimator()
        estimator.add(TimeSyncSample(offset: 5, roundTrip: 0.4))
        estimator.add(TimeSyncSample(offset: 1, roundTrip: 0.05))
        #expect(estimator.offset == 1, "the sample with the fastest round trip must be used")
    }

    // Three or more, and it is the median of the last seven. An outlier does not drag it.
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

    // REQ-COM-009: converts a server time onto this device's own clock.
    @Test func serverTimeIsConvertedToLocalTime() {
        var estimator = TimeSyncEstimator()
        for _ in 0..<3 { estimator.add(TimeSyncSample(offset: 10, roundTrip: 0.1)) }
        let serverEnd = now.addingTimeInterval(1500)
        #expect(estimator.localTime(forServerTime: serverEnd) == serverEnd.addingTimeInterval(-10))
    }

    // REQ-ERR-007: past 5 seconds it is not pushed in by correction; it warns instead.
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

    // REQ-COM-004: exponential backoff, one second the first time and 30 seconds at the cap.
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

    // Reset on success. Forget to, and a link that went bad once waits 30 seconds ever after.
    @Test func successResetsTheBackoff() {
        var policy = ReconnectPolicy()
        _ = policy.nextDelay()
        _ = policy.nextDelay()
        policy.reset()
        #expect(policy.nextDelay() == 1)
    }

    // REQ-COM-005: with no answer for 15 seconds, the connection is taken as lost.
    @Test func heartbeatTimesOutAfterFifteenSeconds() {
        #expect(Heartbeat.interval == 5)
        #expect(!Heartbeat.isStale(lastReceivedAt: now, now: now.addingTimeInterval(15)))
        #expect(Heartbeat.isStale(lastReceivedAt: now, now: now.addingTimeInterval(15.1)))
        #expect(Heartbeat.isStale(lastReceivedAt: nil, now: now))
    }
}
