import Network
import MdoroCore

// REQ-PRT-001: **this end's half of the shared reading of a line.**
//
// `LineRead.of` decides what one read means, and it lives in `MdoroCore` so that the iPhone and the
// Mac cannot answer that question differently. It is stated in `LineFrame`, which names the frame
// kinds without Network.framework in it; this is the translation from the opcode Network.framework
// actually hands over.
//
// **There is a twin of this file in `MdoroMac` (`PomodoroMac/Server/WebSocketFrames.swift`), and it
// has to say the same thing.** The two targets cannot share a file without the project owning it
// (Decision 0013), and putting `NWProtocolWebSocket.Opcode` into `MdoroCore` instead would put
// Network.framework under everything that links the package. So the judgement is shared and this
// list of five names is written twice — **change one and read the other.**
extension LineFrame {
    init(_ opcode: NWProtocolWebSocket.Opcode) {
        switch opcode {
        case .text: self = .text
        case .binary: self = .binary
        case .close: self = .close
        case .ping: self = .ping
        case .pong: self = .pong
        // `.cont`, and whatever a later SDK adds. Neither a message nor an ending.
        default: self = .other
        }
    }
}

extension NWConnection.ContentContext {
    // The frame this read came in, or nil when it came with no WebSocket metadata at all.
    //
    // REQ-COM-004: **nil is not "nothing to see".** A completed, empty read that carries no frame
    // is one of the three endings, and the context being absent is the ordinary way that ending
    // arrives — so the absence is handed to `LineRead.of` rather than swallowed here.
    var webSocketFrame: LineFrame? {
        guard let metadata = protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata else { return nil }
        return LineFrame(metadata.opcode)
    }
}
