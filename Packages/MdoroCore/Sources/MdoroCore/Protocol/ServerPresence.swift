import Foundation

// REQ-COM-003 (v2.25) / Decision 0040: the server and its Bonjour advertisement exist only while
// a pairing does — or while the user is on the pairing screen, raising one. A Mac that never
// pairs an iPhone pays nothing for the feature: no listener, no name on the LAN, and no local
// network permission dialog at launch. The dialog arrives instead at the moment the pairing
// screen is opened, which is the one moment it has its context attached (REQ-PLT-007).
//
// The decision lives here, apart from the code that raises listeners, for the same reason
// `LogDestination` does: the Mac target's tests cannot put a name on the reader's LAN to watch
// the wiring work, but `swift test` can hold the rule itself still.
public enum ServerPresence {

    // REQ-COM-003 (v2.26): **records that could not be read are not records that are absent.**
    // A launch that could not read the token records does not know whether it is paired, and
    // answering "no pairings" would keep it silently off the air with nothing on the screen —
    // the attempt has to happen so that its refusal (`stayOffTheAir`) reaches the user.
    public static func pairingsMayExist(hasPairings: Bool, recordsUnreadable: Bool) -> Bool {
        hasPairings || recordsUnreadable
    }

    // REQ-COM-003 (v2.25): when the server should be up — or, with unreadable records, when the
    // attempt that ends in a reason on the screen should be made.
    // - paired (or possibly paired): at launch, unconditionally
    // - not paired: only while the pairing screen is open
    public static func shouldBeOnTheAir(pairingsMayExist: Bool, pairingScreenIsOpen: Bool) -> Bool {
        pairingsMayExist || pairingScreenIsOpen
    }

    // REQ-UIX-004 (v2.25): a Mac that has never paired is not "Not connected" — it is a Mac in
    // its normal state, and a normal state is not shown in the shape of a problem. The connection
    // state exists on screen only while a pairing does. Unreadable records count as "may exist"
    // here too: hiding the state would hide the one screen area that says why.
    public static func showsConnectionState(hasPairings: Bool, recordsUnreadable: Bool) -> Bool {
        pairingsMayExist(hasPairings: hasPairings, recordsUnreadable: recordsUnreadable)
    }
}
