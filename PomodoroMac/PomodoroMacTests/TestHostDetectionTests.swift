import Testing
import MdoroCore
@testable import MdoroMac

// POL-047: this test target runs inside MdoroMac.app, and the app skips its whole startup
// when `TestHost.isRunning` says so. If the detection ever stops firing, the guard in
// `MdoroMacApp` is still there, `MdoroCoreTests` still passes — and the suite goes back to
// advertising on the LAN and watching the reader's Task.md.
//
// `MdoroCoreTests` checks that the guard exists; only a test hosted by the app can check
// that it triggers.
@Suite("The app knows it is hosting a test run (POL-047)")
struct TestHostDetectionTests {

    @Test func theHostAppSeesThatThisIsATestRun() {
        #expect(TestHost.isRunning, "XCTestConfigurationFilePath is unset in the host process")
    }
}
