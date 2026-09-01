import Testing
import Network
import MdoroCore
@testable import MdoroiOS

// **One Mac can show up as "Name" and "Name (2)" at once — and so can two Macs.** Nothing on
// screen can tell those two situations apart: the number is mDNSResponder settling a name
// collision (`docs/PLATFORM.md`). So none of them is hidden. The rule that used to hide one kept
// the highest number, and the highest number is not the newest.
//
// **What tells them apart to the app is the TXT `id`** (Decision 0040), which is not a thing
// anyone can read off a list — so the list still shows names, number and all.
@Suite("Discovery offers every Mac it found (REQ-ERR-005)")
struct ServerBrowserDiscoveryTests {

    private func server(_ name: String) -> DiscoveredServer {
        DiscoveredServer(
            id: name, name: name,
            endpoint: .service(name: name, type: BonjourService.type, domain: "local.", interface: nil),
            websocketPort: nil,
            serverId: .generate()
        )
    }

    // Three at once is not hypothetical; the product owner has seen three.
    @Test func everyRegistrationOfTheSameNameIsOffered() {
        let found = ServerBrowser.inDisplayOrder(
            [server("Lychee (3)"), server("Lychee"), server("Lychee (2)")]
        )
        #expect(found.count == 3)
        // The number is the only thing on screen that tells them apart, so it is kept.
        #expect(found.map(\.name) == ["Lychee", "Lychee (2)", "Lychee (3)"])
    }

    // The rule that stood here kept "Lychee (2)" and dropped "Lychee". Measurement says the one
    // without a number is the later arrival: a number is never handed back, so the survivor of a
    // collision keeps its "(2)" and the next registration takes the name that came free.
    @Test func theMacWithNoNumberIsNotDroppedForTheOneWithOne() {
        #expect(
            ServerBrowser.inDisplayOrder([server("Lychee (2)"), server("Lychee")]).map(\.id)
                == ["Lychee", "Lychee (2)"]
        )
    }

    // Named, not counted: with nothing folding anything together, a count of two is satisfied by
    // any two things at all.
    @Test func differentMacsAreNotMerged() {
        #expect(
            ServerBrowser.inDisplayOrder([server("Mango"), server("Lychee")]).map(\.name)
                == ["Lychee", "Mango"]
        )
    }

    // NWBrowser hands back a Set, so the order they arrive in is not the order they arrived in
    // last time. A list of same-named Macs that shuffles between callbacks cannot be chosen from.
    @Test func theOrderDoesNotFollowTheOrderTheBrowserGaveThem() {
        let names = ["Mango", "Lychee (2)", "Lychee", "Lychee (10)", "Lychee (3)"]
        let expected = ["Lychee", "Lychee (2)", "Lychee (3)", "Lychee (10)", "Mango"]
        for rotation in 0..<names.count {
            let rotated = Array(names[rotation...] + names[..<rotation])
            #expect(
                ServerBrowser.inDisplayOrder(rotated.map(server)).map(\.name) == expected,
                "starting from \(rotated[0]) gave a different order"
            )
        }
    }
}

// REQ-COM-003 / Decision 0040: the other end of `BonjourService.txtEntries`. The Mac's half is
// checked in `MdoroCoreTests`, which is what CI runs; **this is the half that reads what arrived**,
// and it needs `NWTXTRecord`, which only this target links.
@Suite("What the iPhone reads off the air (REQ-COM-003 / Decision 0040)")
struct AdvertisementReadingTests {

    @Test func thePortAndTheIdentityComeBackOut() throws {
        let id = ServerID.generate()
        let record = NWTXTRecord(BonjourService.txtEntries(websocketPort: 51234, serverId: id))

        let read = ServerBrowser.read(record)
        #expect(read.websocketPort == 51234)
        #expect(read.serverId == id, "Decision 0040: the id the Mac advertised did not come back")
    }

    // A Mac from before Decision 0040 advertises no id. It is still offered — and refuses the
    // connection itself on the version check (REQ-PRT-004) — rather than vanishing from the list
    // with nothing said.
    @Test func anAdvertisementWithNoIdentityIsNotOneWithAnIdentity() {
        let record = NWTXTRecord([BonjourService.websocketPortKey: "51234", BonjourService.versionKey: "1"])
        let read = ServerBrowser.read(record)

        #expect(read.websocketPort == 51234)
        #expect(read.serverId == nil)
    }

    // The value is written by whoever is on the LAN and ends up as a Keychain account name, so
    // anything that is not a UUID is not an id.
    @Test func anIdentifierThatIsNotOneIsNotRead() {
        for junk in ["", "Mdoro (2)", "../../etc/passwd", String(repeating: "a", count: 200)] {
            let record = NWTXTRecord([
                BonjourService.websocketPortKey: "1",
                BonjourService.identityKey: junk,
            ])
            #expect(ServerBrowser.read(record).serverId == nil, "`\(junk)` was taken for an id")
        }
    }
}
