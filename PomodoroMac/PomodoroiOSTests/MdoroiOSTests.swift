import Testing
import Network
@testable import MdoroiOS

// **One Mac shows up twice, as "Name" and "Name (2)".** A Bonjour advertisement that has not
// fully gone away.
@Suite("Deduplicating discovery results")
struct ServerBrowserDeduplicationTests {

    private func server(_ name: String) -> DiscoveredServer {
        DiscoveredServer(
            id: name, name: name,
            endpoint: .service(name: name, type: "_mdoro._tcp", domain: "local.", interface: nil),
            websocketPort: nil
        )
    }

    @Test func keepsOnlyTheNewestOfTheSameName() {
        let result = ServerBrowser.deduplicated([server("Lychee"), server("Lychee (2)"), server("Lychee (3)")])
        #expect(result.count == 1)
        // The number is not shown. To the user this is one machine.
        #expect(result.first?.name == "Lychee")
        // **The newest registration** (the highest number) is the one kept.
        #expect(result.first?.id == "Lychee (3)")
    }

    @Test func differentMacsAreNotMerged() {
        #expect(ServerBrowser.deduplicated([server("Lychee"), server("Mango")]).count == 2)
    }

    @Test func aNameThatMerelyEndsWithParenthesesIsNotASuffix() {
        #expect(ServerBrowser.splitDuplicateSuffix("Mac (work)").base == "Mac (work)")
        #expect(ServerBrowser.splitDuplicateSuffix("Mac (1)").base == "Mac (1)")
        #expect(ServerBrowser.splitDuplicateSuffix("Mac (2)").base == "Mac")
    }
}
