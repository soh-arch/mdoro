import Testing
import Network
@testable import MdoroiOS

// **同じ Mac が「Name」「Name (2)」と重なって見える。** 消えきっていない Bonjour の広告である。
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
        // 番号は表示しない。利用者にとっては1台である。
        #expect(result.first?.name == "Lychee")
        // **いちばん新しい登録**（番号が最大）を残す。
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
