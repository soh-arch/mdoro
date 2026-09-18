import Testing
@testable import MdoroCore

// REQ-ERR-010 / Decision 0034: a failure is recorded as a domain and a code, and our own
// failures carry the `Mdoro` domain with a code fixed per case. That much is written down.
//
// This suite rests on one step past it, which neither the requirement nor the record states: a
// number that has been handed out keeps the meaning it was handed out for, and a number
// withdrawn is never handed out again. The reason is not in the code but in where the code
// goes — it is written into the diagnostic log and the user pastes it into an issue — so
// moving a number does not break anything that runs, it breaks every report filed before the
// move. Until a record says it, the ledger below is where that rule lives.
//
// `ErrorReportingTests.everyCodeInOurOwnDomainMeansOneThing` asks only that no two meanings
// share a number today, which a table where every number moved at once still satisfies. What
// follows is the other half: each number written down beside its meaning, away from the five
// places that hand numbers out, so a number cannot move by an edit to one file.
//
// How to edit the ledger below:
//   * a new case adds a line to its band. The number is the next one that band never used —
//     not the lowest one currently free;
//   * a case that goes away moves its number into `numbersWithdrawnFromUse` and leaves the hole
//     where it is. Closing a hole up puts an old report's number on a new meaning.

private struct CodeBand {
    // The place that hands these numbers out, spelled as the ledger labels them.
    let owner: String
    // The range that place owns, as the comments in `ErrorCode.swift` describe it.
    let numbers: ClosedRange<Int>
    // Meaning (the case or property name) against the number it was handed.
    let allocations: [String: Int]
}

private let codeLedger: [CodeBand] = [
    // The static table in `ErrorCode.swift`, itself divided into 1–9 log, 10–19 state,
    // 20–29 notifications, 30–39 reaching a folder the user picked.
    CodeBand(owner: "ErrorCode", numbers: 1...39, allocations: [
        "logInvalidFilePath": 1,
        "logWouldModifyExistingLines": 2,
        "logFolderNotSet": 3,
        "logFileChangedWhileWriting": 4,
        "stateCorrupted": 10,
        "stateUnsupportedSchemaVersion": 11,
        "identityUnreadable": 12,
        "deviceTokensUnreadable": 13,
        "notificationsNotAllowed": 20,
        "bookmarkCreationFailed": 30,
        "bookmarkResolutionFailed": 31,
        "accessDenied": 32,
    ]),
    // `TimerError.errorCode` in Effect.swift.
    CodeBand(owner: "TimerError", numbers: 40...49, allocations: [
        "invalidStateForAction": 40,
        "extendWindowClosed": 41,
        "settingOutOfRange": 42,
        "presetNotFound": 43,
        "presetLimitReached": 44,
        "presetNameConflict": 45,
        "cannotDeleteLastPreset": 46,
        "cannotDeleteActivePreset": 47,
        "taskNotFound": 48,
    ]),
    // `CommandTranslation.Parameter.errorCode` — the field a malformed `command` got wrong.
    CodeBand(owner: "CommandTranslation.Parameter", numbers: 50...59, allocations: [
        "sessionType": 50,
        "decision": 51,
        "stableId": 52,
        "settings": 53,
        "presetId": 54,
        "preset": 55,
        "orderedIds": 56,
    ]),
    // `AuthFailureCode.errorCode` in ProtocolTypes.swift (10.2 `authFailed.code`).
    // 64 is missing on purpose; see `numbersWithdrawnFromUse`.
    CodeBand(owner: "AuthFailureCode", numbers: 60...69, allocations: [
        "invalidPairingCode": 60,
        "pairingModeNotActive": 61,
        "pairingAttemptsExceeded": 62,
        "unknownDeviceToken": 63,
        "connectionRejectedByUser": 65,
    ]),
    // `ProtocolRefusal.errorCode` beside it — REQ-PRT-004, the refusals 10.2 carries on
    // `error.code` instead.
    CodeBand(owner: "ProtocolRefusal", numbers: 70...79, allocations: [
        "protocolVersionMismatch": 70,
    ]),
]

// Numbers that were handed out and then withdrawn. They are not free again.
//
// 64 was `AuthFailureCode.anotherClientConnected`, removed when REQ-SEC-004 settled that a
// connection already open is a reason to ask rather than to refuse. The number stayed behind:
// it had already been written into logs, and the refusal a reader would look it up for is not
// the refusal that would take it next.
private let numbersWithdrawnFromUse: [Int: String] = [
    64: "AuthFailureCode.anotherClientConnected",
]

// One number as the source actually hands it out.
private struct NumberInUse {
    let owner: String
    let meaning: String
    let code: ErrorCode

    var label: String { "\(owner).\(meaning)" }
}

// Reads every number back from the five places that hand them out.
//
// Four of the five are exhaustive switches over `CaseIterable` enums, so the meanings come from
// the source as well as the numbers. The fifth, the table in `ErrorCode.swift`, is a set of
// static properties whose names no runtime call can recover, so those names are written out
// here — the numbers beside them are still read from the source, which is the half the ledger
// is holding in place.
private func numbersInUse() -> [NumberInUse] {
    let staticTable: [(String, ErrorCode)] = [
        ("logInvalidFilePath", ErrorCode.logInvalidFilePath),
        ("logWouldModifyExistingLines", ErrorCode.logWouldModifyExistingLines),
        ("logFolderNotSet", ErrorCode.logFolderNotSet),
        ("logFileChangedWhileWriting", ErrorCode.logFileChangedWhileWriting),
        ("stateCorrupted", ErrorCode.stateCorrupted),
        ("stateUnsupportedSchemaVersion", ErrorCode.stateUnsupportedSchemaVersion),
        ("identityUnreadable", ErrorCode.identityUnreadable),
        ("deviceTokensUnreadable", ErrorCode.deviceTokensUnreadable),
        ("notificationsNotAllowed", ErrorCode.notificationsNotAllowed),
        ("bookmarkCreationFailed", ErrorCode.bookmarkCreationFailed),
        ("bookmarkResolutionFailed", ErrorCode.bookmarkResolutionFailed),
        ("accessDenied", ErrorCode.accessDenied),
    ]

    var found: [NumberInUse] = staticTable.map {
        NumberInUse(owner: "ErrorCode", meaning: $0.0, code: $0.1)
    }
    found += TimerError.allCases.map {
        NumberInUse(owner: "TimerError", meaning: String(describing: $0), code: $0.errorCode)
    }
    found += CommandTranslation.Parameter.allCases.map {
        NumberInUse(owner: "CommandTranslation.Parameter", meaning: $0.rawValue, code: $0.errorCode)
    }
    found += AuthFailureCode.allCases.map {
        NumberInUse(owner: "AuthFailureCode", meaning: $0.rawValue, code: $0.errorCode)
    }
    found += ProtocolRefusal.allCases.map {
        NumberInUse(owner: "ProtocolRefusal", meaning: $0.rawValue, code: $0.errorCode)
    }
    return found
}

private func ledgerByLabel() -> [String: Int] {
    var result: [String: Int] = [:]
    for band in codeLedger {
        for (meaning, number) in band.allocations {
            result["\(band.owner).\(meaning)"] = number
        }
    }
    return result
}

@Suite("A number in our own domain keeps its meaning (REQ-ERR-010 / Decision 0034)")
struct ACodeKeepsItsMeaningTests {

    // The number against the meaning, both directions. A number that moved fails here, and so
    // does a number handed out without being recorded — the ledger is only an anchor while it
    // covers everything.
    @Test func everyNumberStillMeansWhatItWasHandedOutFor() {
        let inUse = numbersInUse()
        let ledger = ledgerByLabel()

        // A check that read nothing back looks exactly like a check that passed.
        #expect(!inUse.isEmpty, "no numbers were read back — this test is looking at nothing")
        #expect(!ledger.isEmpty, "the ledger is empty — there is nothing holding the numbers")

        let recorded = Array(ledger.values)
        #expect(
            Set(recorded).count == recorded.count,
            "two meanings are recorded on one number; the ledger contradicts itself"
        )

        for entry in inUse {
            #expect(
                entry.code.domain == ErrorCode.ownDomain,
                "\(entry.label) is not in the \(ErrorCode.ownDomain) domain"
            )
            guard let number = ledger[entry.label] else { continue }
            #expect(
                entry.code.code == number,
                """
                \(entry.label) is now \(entry.code.code), recorded as \(number). The recorded \
                number is already in reports the user filed.
                """
            )
        }

        let labelsInUse = Set(inUse.map(\.label))
        let unrecorded = labelsInUse.subtracting(ledger.keys).sorted()
        let missingFromSource = Set(ledger.keys).subtracting(labelsInUse).sorted()
        #expect(
            unrecorded.isEmpty,
            "a number was handed out without being recorded here: \(unrecorded)"
        )
        #expect(
            missingFromSource.isEmpty,
            """
            recorded here but gone from the source: \(missingFromSource). A meaning that goes \
            away withdraws its number; it does not drop the line.
            """
        )
    }

    // The numbers are allocated, not counted off — the half of the rule no record states, held
    // here (see the note at the top of this file). A hole in them is not a free number: it is a
    // number some issue already names, and the meaning it named is gone.
    @Test func aNumberOnceWithdrawnIsNeverHandedOutAgain() {
        let inUse = numbersInUse()
        let ledger = ledgerByLabel()

        #expect(!inUse.isEmpty, "no numbers were read back — this test is looking at nothing")
        #expect(
            !numbersWithdrawnFromUse.isEmpty,
            "no withdrawn number is on record, so this test cannot catch a hole being closed"
        )

        for (number, formerMeaning) in numbersWithdrawnFromUse {
            let takers = inUse.filter { $0.code.code == number }.map(\.label).sorted()
            #expect(
                takers.isEmpty,
                """
                \(number) was withdrawn from \(formerMeaning) and \(takers) took it. A hole \
                stays a hole: a reader looking that number up would find the wrong failure.
                """
            )
            let recordedFor = ledger.filter { $0.value == number }.keys.sorted()
            #expect(
                recordedFor.isEmpty,
                "the ledger hands \(number) to \(recordedFor); it was withdrawn from \(formerMeaning)"
            )
        }
    }

    // Which place owns which range — the bands the comments in `ErrorCode.swift` describe, so
    // that a new case cannot quietly take a number out of somebody else's band.
    @Test func eachPlaceHandsOutOnlyNumbersFromItsOwnBand() {
        let inUse = numbersInUse()
        #expect(!inUse.isEmpty, "no numbers were read back — this test is looking at nothing")

        var bands: [String: ClosedRange<Int>] = [:]
        for band in codeLedger {
            #expect(!band.allocations.isEmpty, "\(band.owner) owns a band and hands out nothing")
            bands[band.owner] = band.numbers
        }

        for entry in inUse {
            guard let band = bands[entry.owner] else {
                Issue.record("\(entry.owner) hands out numbers and has no band on record")
                continue
            }
            #expect(
                band.contains(entry.code.code),
                """
                \(entry.label) is \(entry.code.code), outside \(band.lowerBound)–\
                \(band.upperBound), which is what \(entry.owner) owns.
                """
            )
        }

        // Two places must not be able to reach the same number without noticing each other.
        for first in codeLedger.indices {
            for second in codeLedger.indices where second > first {
                let one = codeLedger[first]
                let other = codeLedger[second]
                #expect(
                    one.numbers.upperBound < other.numbers.lowerBound
                        || other.numbers.upperBound < one.numbers.lowerBound,
                    "\(one.owner) and \(other.owner) own overlapping bands"
                )
            }
        }
    }
}
