import Foundation

// REQ-PRT-001: what a peer needs of an open line, said without Network.framework in it.
//
// The client's handling of what arrives — REQ-ERR-009's run of ten, REQ-PRT-005's forward
// compatibility, REQ-COM-004's reconnect — hangs off a line it cannot open in a test, because an
// `NWConnection` dials the moment it is started. Naming the line as a protocol lets a test stand
// where the LAN does and drive the same handling with the same bytes.
//
// **The vocabulary is `Data` and nothing else.** Framing, opcodes and endpoints belong to the
// implementation; a substitute that had to speak them would be a second implementation.
public enum MessageLinkEvent: Sendable {
    // The line is up. Messages may go out.
    case ready
    // One whole protocol message arrived.
    case message(Data)
    // The line is over — refused, dropped, or cancelled. It does not come back; a new one is opened.
    case ended
}

@MainActor
public protocol MessageLink: AnyObject {
    // Events arrive on the main actor until the line ends.
    func start(onEvent: @escaping (MessageLinkEvent) -> Void)
    func send(_ data: Data)
    func cancel()
}
