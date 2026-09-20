import Testing
import Foundation
import UserNotifications
@testable import MdoroMac

// REQ-COM-014: a `UNCalendarNotificationTrigger` is built from wall-clock fields, and wall-clock
// fields on their own do not name an instant. `DateComponents.timeZone` is what turns
// "10:00, 14 March" into a moment; without it the notification fires at whatever 10:00 means on
// the machine when the time comes, which is a different moment after a flight or a summer-time
// change.
//
// **The check stands on the trigger, not on a copy of the arithmetic.**
// `UNCalendarNotificationTrigger.dateComponents` reads back, so what is asserted here is the object
// the scheduler hands to the notification centre. The centre itself is out of reach for this target
// (see `RecordedNotifications`), which is why `calendarTrigger(for:calendar:)` is reachable on its
// own.
//
// The zone the tests build with is given explicitly rather than taken from the machine: a test that
// resolves the fields in the same zone that produced them passes whether or not the zone was ever
// attached.
@Suite("A pre-notification knows which time zone it was scheduled in (REQ-COM-014)")
@MainActor
struct ANotificationThatKnowsItsTimeZoneTests {

    private static func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    // The line REQ-COM-014 asks for, at its plainest: delete it and this fails.
    @Test func theTriggerCarriesAZoneAtAll() {
        let trigger = NotificationScheduler.calendarTrigger(for: Date(timeIntervalSince1970: 1_800_000_000))

        let zone = trigger.dateComponents.timeZone
        #expect(zone != nil, "REQ-COM-014: the trigger names no time zone, so its fire time is not a moment")
        #expect(zone == Calendar.current.timeZone, "REQ-COM-014: the zone is not the one the fields were read in")
    }

    // The same, made independent of the machine the suite runs on.
    //
    // The fields are produced in Tokyo and resolved by a calendar set to Los Angeles. A trigger that
    // names its zone still means the instant it was scheduled for; one that does not is read in
    // whatever zone is doing the reading, and lands 17 hours out — on any machine, in any zone.
    @Test func theFieldsStillMeanTheSameInstantWhenReadSomewhereElse() throws {
        let fireDate = Date(timeIntervalSince1970: 1_800_000_000)
        let trigger = NotificationScheduler.calendarTrigger(for: fireDate, calendar: Self.calendar("Asia/Tokyo"))

        let elsewhere = Self.calendar("America/Los_Angeles")
        let resolved = try #require(
            elsewhere.date(from: trigger.dateComponents),
            "the components do not describe a date at all"
        )

        let sameInstant = resolved == fireDate
        #expect(sameInstant, "REQ-COM-014: read in another zone the fire time moved to \(resolved), not \(fireDate)")
    }

    // The summer-time half of the clause's reason, and the fields the extraction has to keep.
    //
    // 10:00 on 14 March 2027 in Los Angeles is PDT: the transition was that morning at 02:00. Naming
    // the zone — rather than an offset, or nothing — is what makes the trigger mean 17:00 UTC and not
    // 18:00. Seconds are carried too, so a fire time is not quietly rounded to the minute.
    @Test func aFireTimeAfterASpringForwardMeansTheHourItWasScheduledFor() throws {
        let losAngeles = Self.calendar("America/Los_Angeles")
        let fireDate = try #require(
            losAngeles.date(from: DateComponents(year: 2027, month: 3, day: 14, hour: 10, minute: 30, second: 20)),
            "the fixture date could not be built"
        )

        let components = NotificationScheduler.calendarTrigger(for: fireDate, calendar: losAngeles).dateComponents

        #expect(components.year == 2027)
        #expect(components.month == 3)
        #expect(components.day == 14)
        #expect(components.hour == 10)
        #expect(components.minute == 30)
        #expect(components.second == 20, "the seconds of the fire time were dropped")

        let utc = Self.calendar("UTC")
        let resolved = try #require(utc.date(from: components), "the components do not describe a date at all")
        let sameInstant = resolved == fireDate
        #expect(sameInstant, "REQ-COM-014: across the summer-time change the fire time became \(resolved)")
    }
}
