import Testing
import MdoroCore
@testable import MdoroiOS

// The same check on the phone. Here a startup that runs anyway browses for Bonjour services,
// schedules real notifications and opens a Live Activity on the reader's own device.
// `MdoroCoreTests` checks that the guard in `MdoroiOSApp` exists; only a test hosted by the app
// can check that it triggers.
@Suite("The app knows it is hosting a test run (POL-047)")
struct TestHostDetectionTests {

    @Test func theHostAppSeesThatThisIsATestRun() {
        #expect(
            TestHost.isRunning,
            "POL-111: neither variable the launcher writes is set in the host process"
        )
    }
}
