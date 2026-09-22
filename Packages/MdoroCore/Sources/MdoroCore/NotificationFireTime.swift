import Foundation

// REQ-PRT-001 / REQ-COM-014: the wall-clock fields a local notification is asked to fire at, in
// shared code, so both devices reach the same answer.
//
// **Why this is here and not twice.** Mac and iPhone each schedule their own notifications through
// `UNUserNotificationCenter`, and each was building these fields itself — the same component set,
// the same explicit zone, written out in two files. On 2026-09-20 the explicit zone REQ-COM-014 asks
// for turned out to be on the iPhone side alone; it had been missing on the Mac for close to a year,
// and nothing could say so, because there was no one place for the two answers to come from. The
// component set and the zone are one decision, so they are made once.
//
// **`UserNotifications` does not come in with it.** This package is the protocol and the state
// machine; the OS's notification types stay in the app targets. So what is answered here is
// `DateComponents`, and each side hands it to its own `UNCalendarNotificationTrigger`.
public enum NotificationFireTime {

    // REQ-COM-014: the fields matched on. Down to the second, so a fire time is not rounded to the
    // start of its minute, and no further — a trigger is matched on the fields named here and on
    // nothing else.
    public static let matchedComponents: Set<Calendar.Component> = [
        .year, .month, .day, .hour, .minute, .second,
    ]

    // REQ-COM-014: **`timeZone` is given explicitly.** Wall-clock fields on their own do not name an
    // instant: without the zone, a trip across time zones or a summer-time change moves the moment
    // the notification fires.
    //
    // **The zone is the calendar's own, not `TimeZone.current` read a second time.** The fields are
    // read out of that calendar, so the pair has to come from one place, or the two can disagree and
    // describe a time that never existed. With the default calendar it is the reader's current zone,
    // which is what both app targets want.
    //
    // A `calendar` parameter so a test can stand in a zone it chose rather than in the one the
    // machine running it happens to be in.
    public static func dateComponents(for fireDate: Date, calendar: Calendar = .current) -> DateComponents {
        var components = calendar.dateComponents(matchedComponents, from: fireDate)
        components.timeZone = calendar.timeZone
        return components
    }
}
