import Testing
@testable import MdoroCore

// REQ-COM-003 (v2.25) / REQ-UIX-004 / Decision 0040: the server, the advertisement and the
// connection display exist only while a pairing does. The wiring that raises listeners lives in
// the Mac target and cannot be run without a name reaching the reader's LAN, so the rule is held
// still here, where CI runs.
@Suite("On the air only while a pairing exists (REQ-COM-003 v2.25)")
struct ServerPresenceTests {

    // Decision 0040: the user this is all for. No listener, no name on the LAN, no permission
    // dialog at launch — nothing paid for a feature never used.
    @Test func aMacThatNeverPairedStaysOffTheAir() {
        #expect(!ServerPresence.shouldBeOnTheAir(pairingsMayExist: false, pairingScreenIsOpen: false))
    }

    // REQ-COM-003: paired means up at launch, with no screen open anywhere.
    @Test func aPairedMacGoesUpAtLaunch() {
        #expect(ServerPresence.shouldBeOnTheAir(pairingsMayExist: true, pairingScreenIsOpen: false))
    }

    // REQ-COM-003 / REQ-PLT-007: the pairing screen is what raises the server for the first
    // pairing — and is thereby the moment the local network permission dialog appears, with its
    // context attached, instead of at an unexplained first launch.
    @Test func openingThePairingScreenPutsAnUnpairedMacOnTheAir() {
        #expect(ServerPresence.shouldBeOnTheAir(pairingsMayExist: false, pairingScreenIsOpen: true))
    }

    // REQ-COM-003: closing the screen without having paired takes it all down again. (With a
    // pairing on record the closed screen changes nothing — the first row above.)
    @Test func closingTheScreenUnpairedTakesItDown() {
        let open = ServerPresence.shouldBeOnTheAir(pairingsMayExist: false, pairingScreenIsOpen: true)
        let closed = ServerPresence.shouldBeOnTheAir(pairingsMayExist: false, pairingScreenIsOpen: false)
        #expect(open && !closed)
    }

    // REQ-COM-003 (v2.26): unreadable is not empty. The launch that could not read its records
    // has to make the attempt, because the attempt is what puts the reason on the screen.
    @Test func unreadableRecordsCountAsPairingsThatMayExist() {
        #expect(ServerPresence.pairingsMayExist(hasPairings: false, recordsUnreadable: true))
        #expect(ServerPresence.pairingsMayExist(hasPairings: true, recordsUnreadable: false))
        #expect(!ServerPresence.pairingsMayExist(hasPairings: false, recordsUnreadable: false))
    }

    // REQ-UIX-004 (v2.25): "Not connected" is not shown to someone who never paired — a normal
    // state is not shown in the shape of a problem. It comes back the moment a pairing exists,
    // and stays for a launch whose records could not be read, because that state is not normal.
    @Test func theConnectionStateExistsOnlyWhileAPairingDoes() {
        #expect(!ServerPresence.showsConnectionState(hasPairings: false, recordsUnreadable: false))
        #expect(ServerPresence.showsConnectionState(hasPairings: true, recordsUnreadable: false))
        #expect(ServerPresence.showsConnectionState(hasPairings: false, recordsUnreadable: true))
    }
}
