import Foundation

// REQ-ERR-010: the end time the iPhone is counting toward, as the diagnostic log carries it.
//
// The iPhone derives its countdown from `sessionEndAt` alone (REQ-COM-009), so a pasted log has to show that value
// wherever it is set or moved — a start, a resume, an extension, a restored session confirmed, a relaunch.
// Rebuilding it from the start line and the header's lengths breaks as soon as an extension, a
// preset switch or a restore happens in between. Only times and counts go in (Decision 0018).
public enum SessionEndDiagnostics {

    // `endAt` is the value the Mac broadcasts: set only while RUNNING, `none` otherwise.
    // `extendedBy` is the seconds an accepted extension added; nil leaves the field out.
    public static func fields(after context: TimerContext, extendedBy: Int? = nil) -> [DiagnosticField] {
        var fields: [DiagnosticField] = []
        if let extendedBy {
            fields.append(DiagnosticField("by", extendedBy))
        }
        if context.runState == .running, let endAt = context.sessionEndAt {
            fields.append(DiagnosticField("endAt", DiagnosticLogFormat.timestamp(endAt)))
        } else {
            fields.append(DiagnosticField("endAt", "none"))
        }
        return fields
    }
}
