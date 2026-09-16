import Testing
import Foundation
@testable import MdoroCore

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func scratchDirectory() throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("MdoroIdentityTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func discard(_ directory: URL) {
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try? FileManager.default.removeItem(at: directory)
}

@Suite("A Mac is identified by an id, not by a name (REQ-COM-003 / Decision 0040)")
struct ServerIdentityTests {

    // The whole point of the type. A name is a String and this is not, so the two cannot be
    // swapped by accident at a call site — which is how the iPhone came to file its pairing
    // under a name the OS rewrites.
    @Test func onlyAUuidIsAnIdentifier() {
        #expect(ServerID("not an id") == nil)
        #expect(ServerID("") == nil)
        #expect(ServerID("Mdoro (2)") == nil, "a Bonjour instance name is not an identifier")
        let uuid = UUID()
        #expect(ServerID(uuid.uuidString)?.value == uuid.uuidString)
        // TXT records are written by whoever is on the LAN, and this ends up as a Keychain
        // account name, so the shape is settled on the way in and lower case is accepted.
        #expect(ServerID(uuid.uuidString.lowercased()) == ServerID(uuid.uuidString))
    }

    @Test func twoIdentifiersAreNotTheSameIdentifier() {
        #expect(ServerID.generate() != ServerID.generate())
    }

    // It travels in a TXT record and in a file holding nothing else, so it is one string on the
    // wire and not an object with a field in it.
    @Test func itIsCarriedAsOneString() throws {
        let id = ServerID.generate()
        let encoded = try JSONEncoder().encode(id)
        #expect(String(data: encoded, encoding: .utf8) == "\"\(id.value)\"")
        #expect(try JSONDecoder().decode(ServerID.self, from: encoded) == id)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ServerID.self, from: Data("\"Mdoro\"".utf8))
        }
    }

    // Decision 0040: made once, and never again. Everything paired with this Mac is filed under
    // it, so a second answer is every iPhone unpaired with nothing said.
    @Test func theIdentityIsMadeOnceAndReadBackAfterwards() throws {
        let directory = try scratchDirectory()
        defer { discard(directory) }
        let file = ServerIdentityFile(fileURL: directory.appendingPathComponent("identity.json"))

        let first = file.loadOrCreate()
        #expect(first.problem == nil)
        #expect(first.id != nil)

        for _ in 0..<3 {
            let again = file.loadOrCreate()
            #expect(again.id == first.id, "Decision 0040: the id changed between launches")
            #expect(again.problem == nil)
        }

        // A second reader of the same file — a new process, in effect — sees the same answer.
        let reopened = ServerIdentityFile(fileURL: file.fileURL).loadOrCreate()
        #expect(reopened.id == first.id)
    }

    // It is kept beside `state.json` rather than inside it, because Decision 0036 sets that file
    // aside whole when it cannot be read and carries on from defaults. Losing a timer's state is
    // recoverable; losing the identity unpairs every iPhone at once.
    @Test func theIdentityOutlivesTheStateFileBeingSetAside() throws {
        let directory = try scratchDirectory()
        defer { discard(directory) }
        let store = FileStateStore(fileURL: directory.appendingPathComponent("state.json"))
        let file = ServerIdentityFile(fileURL: directory.appendingPathComponent("identity.json"))
        let id = file.loadOrCreate().id

        try Data("this is not JSON".utf8).write(to: store.fileURL)
        let setAside = try store.setAsideUnreadableState()
        #expect(setAside != nil, "the state file must actually have been set aside")

        #expect(file.loadOrCreate().id == id, "the identity went with the state file")
    }

    // Nothing readable is in there to lose, and leaving it would make a new id on every launch.
    // **The caller is told**, because an identity that is not kept is not an identity.
    @Test func aFileWithNothingWeKnowInItIsReplacedAndReported() throws {
        let directory = try scratchDirectory()
        defer { discard(directory) }
        let file = ServerIdentityFile(fileURL: directory.appendingPathComponent("identity.json"))
        try Data("{\"id\":\"Mdoro (2)\"}".utf8).write(to: file.fileURL)

        let outcome = file.loadOrCreate()
        #expect(outcome.problem == .identityUnreadable)
        // **Broken is not unreadable.** This one was handed over, and nothing usable was in it,
        // so there is an id to go on the air with (REQ-COM-003 v2.26).
        #expect(outcome.id != nil)
        // Replaced, so the next launch is steady again rather than making a third id.
        #expect(file.loadOrCreate().id == outcome.id)
        #expect(file.loadOrCreate().problem == nil)
    }

    // A read that failed once may well succeed next launch. Writing over it here would turn a
    // passing fault into every pairing lost, so the file is left exactly as it is.
    @Test func aFileThatCouldNotBeReadIsLeftAlone() throws {
        let directory = try scratchDirectory()
        defer { discard(directory) }
        let file = ServerIdentityFile(fileURL: directory.appendingPathComponent("identity.json"))
        let kept = file.loadOrCreate().id
        let before = try Data(contentsOf: file.fileURL)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.fileURL.path)
        try #require(
            (try? Data(contentsOf: file.fileURL)) == nil,
            "the file system must actually refuse, or this proves nothing"
        )

        let outcome = file.loadOrCreate()
        #expect(outcome.problem != nil, "a failure to read must not pass for success")
        #expect(outcome.problem != .identityUnreadable, "this is not a file we could read")

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.fileURL.path)
        #expect(try Data(contentsOf: file.fileURL) == before, "the file was written over")
        #expect(file.loadOrCreate().id == kept, "the identity did not survive a refused read")
    }

    // REQ-COM-003 (v2.26): **a read that was refused hands back no id at all.**
    //
    // Standing in a new one and going on the air with it does the same damage from the other
    // side as writing over the file would: the Mac is one nobody has heard of, every paired
    // iPhone is asked for a six-digit code, and the token issued in reply is filed under an id
    // that is gone at the next launch. Orphans on both ends. **The Mac stays off the air until
    // it can read who it is** — which is what an empty answer here makes the caller do.
    @Test func aReadThatWasRefusedHandsBackNoIdentityToGoOnTheAirWith() throws {
        let directory = try scratchDirectory()
        defer { discard(directory) }
        let file = ServerIdentityFile(fileURL: directory.appendingPathComponent("identity.json"))
        let kept = try #require(file.loadOrCreate().id)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.fileURL.path)
        try #require(
            (try? Data(contentsOf: file.fileURL)) == nil,
            "the file system must actually refuse, or this proves nothing"
        )

        let outcome = file.loadOrCreate()
        #expect(outcome.id == nil, "REQ-COM-003: an id was invented for a Mac that already has one")
        #expect(outcome.id != kept)
        guard case .unreadable = outcome else {
            Issue.record("a refused read is `unreadable`, not an identity: \(outcome)")
            return
        }
        // REQ-ERR-010 / Decision 0034: and the reason is written in the one shape.
        #expect(outcome.diagnosticSummary?.hasPrefix("unreadable(") == true)

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.fileURL.path)
        #expect(file.loadOrCreate().id == kept, "the identity did not survive a refused read")
    }

    // REQ-COM-003 (v2.27): **an id that could not be written down is handed to nobody.** It is
    // gone at the next launch, so a pairing made under it is an orphan by design — v2.26 handed
    // it out with a warning attached, and the warning was ignorable.
    @Test func anIdentityThatCannotBeWrittenIsNoIdentityAtAll() throws {
        let directory = try scratchDirectory()
        defer { discard(directory) }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let file = ServerIdentityFile(fileURL: directory.appendingPathComponent("identity.json"))

        let outcome = file.loadOrCreate()
        try #require(
            !FileManager.default.fileExists(atPath: file.fileURL.path),
            "the file system must actually refuse, or this proves nothing"
        )
        #expect(outcome.problem != nil, "REQ-ERR-010: the failure was swallowed")
        #expect(outcome.id == nil, "REQ-COM-003 v2.27: an id nobody will see again was handed out")
        guard case .notKept = outcome else {
            Issue.record("a write that was refused is `notKept`, not \(outcome)")
            return
        }
        // **Being unable to write is not being unable to read** — the two keep the Mac off the
        // air for different reasons, and the log has to say which happened.
        #expect(outcome.diagnosticSummary?.hasPrefix("notKept(") == true)

        // And it is not permanent: a launch that can write again is identified as usual.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let recovered = file.loadOrCreate()
        #expect(recovered.id != nil, "a write that succeeded left the Mac off the air")
        #expect(recovered.problem == nil)
    }
}

@Suite("What goes on the air (REQ-COM-003 / Decision 0040)")
struct BonjourAdvertisementTests {

    // The TXT record used to carry `ws` and `v` and nothing else: **no value on the air said
    // which Mac this was.** The name could not, because mDNSResponder rewrites it.
    @Test func theRecordCarriesThePortTheVersionAndTheIdentity() {
        let id = ServerID.generate()
        let entries = BonjourService.txtEntries(websocketPort: 51234, serverId: id)

        #expect(entries[BonjourService.websocketPortKey] == "51234")
        #expect(entries[BonjourService.versionKey] == String(PomodoroProtocol.version))
        #expect(entries[BonjourService.identityKey] == id.value)
        #expect(ServerID(entries[BonjourService.identityKey] ?? "") == id)
    }

    // REQ-PRT-004: the version on the air is the version that is spoken. A record that named a
    // different one would have the iPhone refusing a Mac it can talk to, or dialling one it cannot.
    @Test func theVersionOnTheAirIsTheVersionInTheProtocol() throws {
        let entries = BonjourService.txtEntries(websocketPort: 1, serverId: .generate())
        let announced = try #require(Int(entries[BonjourService.versionKey] ?? ""))
        #expect(announced == PomodoroProtocol.version)
        #expect(PomodoroProtocol.isCompatible(announced))
    }

    // Decision 0024: both ends read the type from here, so they cannot drift apart.
    @Test func theServiceTypeIsMdoros() {
        #expect(BonjourService.type == "_mdoro._tcp")
    }

    // Decision 0040 (judgement 5): a registration that came back renamed (` (2)`) is the one
    // piece of evidence another Mdoro shares the LAN; one that came back as asked is nothing to
    // mention.
    @Test func aRenamedRegistrationIsEvidenceAndAnExactOneIsNot() {
        #expect(BonjourService.alternateRegisteredName(registered: "Mdoro (2)", requested: "Mdoro") == "Mdoro (2)")
        #expect(BonjourService.alternateRegisteredName(registered: "Mdoro", requested: "Mdoro") == nil)
    }
}

@Suite("The name the iPhone sees (9.3 displayName / Decision 0040)")
struct DisplayNameTests {

    // 9.3: the default is the app's name and not the Mac's, because the Mac's usually has a
    // person in it — and it went out over the LAN, in `welcome`, and onto a lock screen.
    @Test func theDefaultIsTheAppsOwnName() {
        #expect(AppSettings.default.displayName == "Mdoro")
        #expect(AppSettings.defaultDisplayName == AppInfo.name)
    }

    // 9.3: one character or more. REQ-CFG-018 refuses an out-of-range value that arrives over the
    // wire rather than applying it, and this is the check that answers for this field.
    @Test func aNameHasToBeANameEvenWhenItArrivesFromTheiPhone() {
        var settings = AppSettings.default
        settings.displayName = ""
        #expect(!settings.isWithinValidRanges())
        settings.displayName = "   \n "
        #expect(!settings.isWithinValidRanges(), "whitespace advertises a row nothing can read")
        settings.displayName = "M"
        #expect(settings.isWithinValidRanges())
        settings.displayName = "書斎の Mac"
        #expect(settings.isWithinValidRanges(), "what the user types is theirs")
    }

    // REQ-PER-002: a saved file written before this setting existed still reads, and gets the
    // default rather than an empty name that would refuse every later change.
    @Test func aSavedFileFromBeforeThisSettingStillReads() throws {
        let json = Data("""
        {"appearance":"system","focusViewDimmed":false,"logicalDayStartHour":4,
         "idleResetHours":12,"logFileName":"MdoroLog.md","showCompletedTasks":false,
         "logTaskAsLink":false,"logDailySummary":false,"enterFocusViewOnRotate":true,
         "menuBarDisplayMode":"timeAndType","launchAtLogin":false}
        """.utf8)
        let settings = try MessageCoder.decoder.decode(AppSettings.self, from: json)
        #expect(settings.displayName == AppSettings.defaultDisplayName)
        #expect(settings.isWithinValidRanges())
    }
}

@Suite("A token is a record, not a value (REQ-SEC-002 / Decision 0040)")
struct DeviceTokenRecordTests {

    // The Mac used to keep a `Set<String>`, so the device name and the issue date were dropped
    // at the moment of saving. **That is why there was no revocation screen to build**: nothing
    // was left to put on it.
    @Test func pairingKeepsWhoAndWhen() {
        var auth = Authenticator()
        auth.beginPairing(code: "123456", now: t0)
        guard case let .accept(token) = auth.authenticate(
            HelloPayload(deviceToken: nil, pairingCode: "123456", deviceName: "Nori's iPhone"), now: t0
        ) else {
            Issue.record("the correct pairing code was not accepted")
            return
        }

        #expect(auth.issuedTokens.count == 1)
        let kept = auth.issuedTokens[0]
        #expect(kept.value == token.value)
        #expect(kept.deviceName == "Nori's iPhone")
        #expect(kept.issuedAt == t0)
    }

    // `issuedAt` means when it was issued, so the record on file is handed back rather than
    // rebuilt from the hello: rebuilt on every reconnect it shows today's date beside a pairing
    // made months ago — and the revocation screen (Decision 0040) is built to be read.
    @Test func reconnectingDoesNotMoveTheDateItWasIssued() {
        let issued = DeviceToken(value: "tok", deviceName: "Nori's iPhone", issuedAt: t0)
        var auth = Authenticator(issuedTokens: [issued])
        let muchLater = t0.addingTimeInterval(90 * 24 * 3600)

        guard case let .accept(token) = auth.authenticate(
            HelloPayload(deviceToken: "tok", deviceName: "A renamed iPhone"), now: muchLater
        ) else {
            Issue.record("the issued token did not get through")
            return
        }
        #expect(token == issued)
        #expect(token.issuedAt == t0, "the issue date followed the reconnect")
        #expect(auth.issuedTokens == [issued], "a reconnect is not a second pairing")
    }

    // What the Keychain holds is this, encoded. All three fields have to survive the trip, or the
    // record is a value again with extra steps. The names are in arbitrary user languages — a
    // device name is whatever its owner typed into Settings, and a round trip through JSON is
    // where a right-to-left one would come back wrong.
    @Test func theRecordSurvivesBeingSavedAndReadBack() throws {
        let records = [
            DeviceToken(value: "a", deviceName: "Nori's iPhone", issuedAt: t0),
            DeviceToken(value: "b", deviceName: "آيفون العمل", issuedAt: t0.addingTimeInterval(3600)),
        ]
        let data = try MessageCoder.encoder.encode(records)
        let read = try MessageCoder.decoder.decode([DeviceToken].self, from: data)

        #expect(read == records)
        for (before, after) in zip(records, read) {
            #expect(after.value == before.value)
            #expect(after.deviceName == before.deviceName)
            #expect(after.issuedAt == before.issuedAt)
        }
    }
}

// The rules above are kept by the app targets, which `swift test` cannot link. Reading their
// source is how they stay checked in CI — the same route `StringCatalogTests` and
// `ColorLiteralTests` already take. The helpers are in `RepositorySources.swift`.
@Suite("One name space each side (Decision 0040)")
struct NameSpaceTests {

    // Decision 0040: the Keychain account is the id and never a `String` holding whatever "server
    // name" is nearest — the Bonjour instance name where it is saved, `welcome.serverName` where it
    // is read. Keyed on either, mDNSResponder renaming a registration to `Mdoro (2)` turns a paired
    // Mac into an unknown one, and the iPhone asks for a six-digit code it has already been given.
    @Test func theiPhoneFilesItsPairingUnderTheIdAndNotAName() throws {
        let keychain = withoutComments(try source("PomodoroMac/PomodoroiOS/Client/TokenKeychain.swift"))

        #expect(
            keychain.contains("kSecAttrAccount as String: serverId.value"),
            "Decision 0040: the account name is the id"
        )
        #expect(
            !keychain.contains("serverName"),
            "Decision 0040: a display name has no business in this file"
        )
        // REQ-SEC-002: not carried off in a backup and restored onto another phone, which the Mac
        // would let in — it knows only that the token is one it issued.
        #expect(
            keychain.contains("kSecAttrAccessibleWhenUnlockedThisDeviceOnly"),
            "REQ-SEC-002: the token is not marked as belonging to this device alone"
        )
    }

    // Decision 0040: a Mac is never found by matching one name against another. `client.serverName`
    // (from `welcome`) and `servers.first?.name` (from Bonjour) are two different names for the same
    // Mac, so a match between them falls through to `servers.first` every time they differ — and
    // any time two Macs are listed.
    @Test func theiPhoneNeverFindsAMacByComparingNames() throws {
        let model = withoutComments(try source("PomodoroMac/PomodoroiOS/ClientModel.swift"))

        #expect(!model.contains("$0.name =="), "Decision 0040: a Mac is not found by matching names")
        #expect(!model.contains("servers.first?.name"), "Decision 0040: nor by taking the first name going")
    }

    // Decision 0040: **the Mac's own name does not leave the Mac.** Sent in `welcome` it goes on
    // into the iPhone's Keychain and onto its lock screen, and it is the one string here most
    // likely to have a person's name in it.
    @Test func theMacsOwnNameGoesNowhere() throws {
        for (name, text) in try swiftFiles(under: "PomodoroMac/PomodoroMac", recursive: true) {
            #expect(
                !text.contains("Host.current()"),
                "Decision 0040: \(name) reads the name of the machine"
            )
        }
    }

    // REQ-SEC-002 / Decision 0040: the Mac's side of the same move. The tokens sat in
    // `UserDefaults` as a plain array of values — the secret in a plist anything can read, and the
    // device name and the issue date dropped on the way in.
    @Test func theMacKeepsItsTokensWhereTheiPhoneKeepsIts() throws {
        let store = withoutComments(try source("PomodoroMac/PomodoroMac/Server/DeviceTokenStore.swift"))

        #expect(store.contains("kSecClassGenericPassword"), "Decision 0040: the records are in the Keychain")
        #expect(
            !store.contains("defaults.stringArray"),
            "Decision 0040: nothing is read back out of the plist"
        )
        #expect(
            !store.contains("defaults.set("),
            "Decision 0040: and nothing is written into it either"
        )
        // Not a migration — nothing is read out of it. Secrets left lying in a plist are worse
        // than a key nobody looks at.
        #expect(store.contains("removeObject(forKey: key)"), "the plaintext leftover is not erased")
    }

    // REQ-PRT-001: the type and the TXT keys are written once, in the package both ends link.
    // A key spelled differently on one side is not a build error — it is a Mac that answers and
    // cannot be paired with.
    @Test func bothEndsReadTheServiceTypeFromOnePlace() throws {
        for folder in ["PomodoroMac/PomodoroMac", "PomodoroMac/PomodoroiOS"] {
            for (name, text) in try swiftFiles(under: folder, recursive: true) {
                #expect(
                    !text.contains("\"\(BonjourService.type)\""),
                    "REQ-PRT-001: \(name) spells the service type out a second time"
                )
            }
        }
    }
}

// REQ-SEC-002 / Decision 0040: **a record is not emptied on the way to being written.**
//
// A `save` that is `SecItemDelete` then `SecItemAdd` with its `OSStatus` discarded, and a `load`
// that folds every status other than `errSecSuccess` into `[]`, are each enough to lose the lot:
// an add that fails leaves the reader with nothing on file and no trace of it anywhere; a read
// that fails answers "nothing paired", so the next pairing writes one record over all of them.
// Both are reachable once the records live in the Keychain rather than in a plist.
//
// The Keychain itself cannot be exercised here: under `xcodebuild` the suite runs inside
// MdoroMac.app and writes into the reader's own login keychain. What this holds is the shape of
// the calls; the policy built on them is `DeviceTokenRecordTests` in the Mac target.
@Suite("Records are not destroyed on the way to being written (REQ-SEC-002 / Decision 0040)")
struct DeviceTokenStorageTests {

    private var store: String {
        get throws { try source("PomodoroMac/PomodoroMac/Server/DeviceTokenStore.swift") }
    }

    @Test func nothingIsRemovedBeforeTheWriteThatReplacesIt() throws {
        let text = withoutComments(try store)
        #expect(
            !text.contains("SecItemDelete"),
            "REQ-SEC-002: the records are emptied before the write that replaces them, and a failed write leaves none"
        )
        #expect(
            text.contains("SecItemUpdate"),
            "REQ-SEC-002: an item that is already there is no longer updated in place"
        )
    }

    // REQ-ERR-010: **a discarded `OSStatus` is a failure nobody hears about.** Every call has to
    // put its answer somewhere a decision can read it.
    @Test func everyKeychainCallHasItsStatusRead() throws {
        // The call, not the word: `errSecItemNotFound` also carries `SecItem` in it.
        let names = ["SecItemCopyMatching(", "SecItemAdd(", "SecItemUpdate(", "SecItemDelete("]
        let calls = withoutComments(try store)
            .split(separator: "\n")
            .filter { line in names.contains { line.contains($0) } }
        #expect(!calls.isEmpty, "the Keychain calls moved; this scan is swinging at nothing")
        for call in calls {
            #expect(
                call.contains(" = SecItem"),
                "REQ-ERR-010: `\(call.trimmingCharacters(in: .whitespaces))` throws its OSStatus away"
            )
        }
    }

    // Decision 0040: **"nothing on record" and "could not be read" are different answers.** Fold
    // them together and one refusal from the Keychain reads as an unpaired Mac.
    @Test func anEmptyKeychainIsToldApartFromOneThatWouldNotAnswer() throws {
        let text = withoutComments(try store)
        #expect(
            text.contains("errSecItemNotFound"),
            "Decision 0040: every failed read answers `nothing paired` again"
        )
        #expect(
            text.contains("case unreadable("),
            "Decision 0040: a read that failed no longer says so, and the next save writes over what it could not read"
        )
    }

    // Decision 0040: `UserDefaults.standard` under this bundle identifier is the reader's own
    // settings, and the suite runs inside the app. Erasing the leftover plist is part of the seam
    // for exactly the reason the rest of it exists — a static call outside the seam is a call a
    // test makes for real, on the machine of whoever ran it.
    @Test func theLeftoverPlistIsErasedThroughTheSeamAndNowhereElse() throws {
        #expect(
            withoutComments(try store).contains("func eraseLeftoverPlaintext()"),
            "POL-047: the seam no longer covers the plist the tokens used to sit in"
        )
        for directory in ["PomodoroMac/PomodoroMac", "PomodoroMac/PomodoroMacTests"] {
            for (name, text) in try swiftFiles(under: directory, recursive: true)
            where name != "DeviceTokenStore.swift" {
                #expect(
                    !text.contains("LeftoverPlaintextTokens"),
                    "POL-047: \(name) empties the reader's own UserDefaults from outside the seam"
                )
            }
        }
    }
}

// Decision 0040: `theMacsOwnNameGoesNowhere` watches that the host name never leaves. **This
// watches that the chosen one arrives** — without it the rename branch could be deleted whole and
// `provideDisplayName` pinned to a literal, with every test in the repository still passing.
@Suite("The name the user chose is the name that travels (Decision 0040)")
struct DisplayNameTravelTests {

    private var appModel: String {
        get throws { withoutComments(try source("PomodoroMac/PomodoroMac/AppModel.swift")) }
    }

    // The two places 9.3 `displayName` has to reach: `welcome.serverName` and the Bonjour
    // instance name. (`ServerInfo` was the third until REQ-COM-002 v2.25 removed `GET /info`.)
    @Test func theChosenNameIsWhatGoesOutInWelcomeAndOnTheAir() throws {
        let text = try appModel
        #expect(
            text.contains("provideDisplayName: { [weak self] in self?.settings.displayName"),
            "Decision 0040: `welcome.serverName` is not the name the user chose"
        )
        #expect(
            text.contains("server.advertise(displayName: settings.displayName"),
            "Decision 0040: the Bonjour instance name is not the name the user chose"
        )
    }

    // 9.5 group C: the name applies at once, and the LAN is where it shows. A name that only
    // reaches the settings file is half a setting.
    @Test func changingTheNameReachesTheAir() throws {
        let text = try appModel
        let branch = try #require(
            text.range(of: "settings.displayName != previous.displayName"),
            "Decision 0040: nothing at all happens when the name changes"
        )
        let body = text[branch.upperBound...].prefix(120)
        #expect(body.contains("readvertise()"), "Decision 0040: the old name stays on the air")
    }

    // REQ-COM-003 / Decision 0040: what a re-advertisement needs to know is whether the Mac is on
    // the air, which is the port — never the listener it is about to fold and raise again. Read a
    // failed rename off the listener object and **one failed rename closes the door on every later
    // one**.
    @Test func aRenameThatFailedDoesNotShutTheDoorOnTheNext() throws {
        let text = try appModel
        let function = try #require(
            text.range(of: "private func readvertise() {"),
            "Decision 0040: `readvertise` is gone; a rename no longer reaches the air"
        )
        let firstStatement = text[function.upperBound...]
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        #expect(
            firstStatement?.hasPrefix("guard") == true,
            "`readvertise` no longer checks it has anywhere to advertise: \(firstStatement ?? "nothing")"
        )
        #expect(
            firstStatement?.contains("infoServer") == false,
            "POL-114: a rename is refused because the last advertisement failed: \(firstStatement ?? "nothing")"
        )
    }
}
