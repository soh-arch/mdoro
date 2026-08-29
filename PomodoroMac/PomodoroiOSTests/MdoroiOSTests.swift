import Testing
import Network
@testable import MdoroiOS

// **One Mac can show up as "Name" and "Name (2)" at once — and so can two Macs.** Nothing here
// can tell those two situations apart: the number is mDNSResponder settling a name collision,
// and the advertisement carries no identifier saying which registration it belongs to
// (`docs/PLATFORM.md`). So none of them is hidden. The rule that used to hide one kept the
// highest number, and the highest number is not the newest.
@Suite("Discovery offers every Mac it found (REQ-ERR-005)")
struct ServerBrowserDiscoveryTests {

    private func server(_ name: String) -> DiscoveredServer {
        DiscoveredServer(
            id: name, name: name,
            endpoint: .service(name: name, type: "_mdoro._tcp", domain: "local.", interface: nil),
            websocketPort: nil
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
