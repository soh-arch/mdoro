import Testing
import MdoroCore
@testable import MdoroMac

// This test target runs inside MdoroMac.app, and the app skips its whole startup when
// `TestHost.isRunning` says so. Let the detection stop firing and the guard in `MdoroMacApp` is
// still there and `MdoroCoreTests` still passes, while the suite advertises on the LAN and
// watches the reader's Task.md.
//
// `MdoroCoreTests` checks that the guard exists; only a test hosted by the app can check
// that it triggers.
@Suite("The app knows it is hosting a test run")
struct TestHostDetectionTests {

    @Test func theHostAppSeesThatThisIsATestRun() {
        #expect(
            TestHost.isRunning,
            "neither variable the launcher writes is set in the host process"
        )
    }
}
