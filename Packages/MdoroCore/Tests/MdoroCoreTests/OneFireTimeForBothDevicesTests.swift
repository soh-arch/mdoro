import Testing
import Foundation
@testable import MdoroCore

// REQ-PRT-001 / REQ-COM-014: the wall-clock fields a local notification fires at are decided once,
// in `NotificationFireTime`, and both app targets ask that function.
//
// **Why the scan below exists at all.** The component set and the explicit zone used to be written
// out in both schedulers. Nothing could see the two come apart, and they did: REQ-COM-014's
// `timeZone` was on the iPhone side alone for close to a year. Moving the arithmetic into this
// package makes one answer possible; it does not stop a third copy being written next to a call, and
// **a copy next to a call fires at a different instant while every test here still passes.** So the
// two files are read, the same way `ColorLiteralTests` reads the views: `swift test` cannot link the
// app targets, and the Mac's own suite does not run in CI.

private let schedulers = [
    "PomodoroMac/PomodoroMac/Services/NotificationScheduler.swift",
    "PomodoroMac/PomodoroiOS/Client/NotificationScheduler.swift",
]

// What a hand-rolled fire time looks like from outside: building `DateComponents` from a calendar
// anywhere but in that one function, or assigning a zone onto components of its own.
//
// Spelled as a function over text rather than over a path, so the scan itself can be handed text
// whose answer is known — see `theScanItselfIsChecked` below.
private func handRolledFireTimeBuilding(in source: String) -> [String] {
    let code = withoutComments(source)
    var findings: [String] = []
    // One piece per occurrence, each ending where that occurrence begins.
    for before in code.components(separatedBy: "dateComponents(").dropLast()
    where !before.hasSuffix("NotificationFireTime.") {
        findings.append("a `dateComponents(` that is not `NotificationFireTime.dateComponents(`")
    }
    if code.contains(".timeZone =") {
        findings.append("a `.timeZone =` assignment onto components built here")
    }
    return findings
}

@Suite("One fire time for both devices (REQ-PRT-001 / REQ-COM-014)")
struct OneFireTimeForBothDevicesTests {

    @Test func bothSchedulersTakeTheirFireTimeFromOnePlace() throws {
        for path in schedulers {
            let text = try source(path)

            // **The one failure a scan like this has**: reading nothing and passing. A stripper that
            // returned "" would satisfy every `contains` below by vacuum, so the positive anchors come
            // first — this file really is a scheduler that builds a calendar trigger, and it really does
            // ask the shared function for the fields.
            let code = withoutComments(text)
            #expect(!code.isEmpty, "\(path) read as empty — the file moved, or stripping comments ate it")
            guard code.contains("UNCalendarNotificationTrigger(dateMatching:") else {
                throw MissingAnchor(path: path, anchor: "UNCalendarNotificationTrigger(dateMatching:")
            }
            guard code.contains("NotificationFireTime.dateComponents(for:") else {
                throw MissingAnchor(path: path, anchor: "NotificationFireTime.dateComponents(for:")
            }

            let found = handRolledFireTimeBuilding(in: text)
            #expect(
                found.isEmpty,
                Comment(rawValue: "\(path) builds a notification fire time of its own: "
                    + found.joined(separator: ", ")
                    + " — REQ-PRT-001: the fields and the zone are `NotificationFireTime`'s answer")
            )
        }
    }

    // **The scan is made to fail, and made to pass.** A detector that answers "nothing wrong" for every
    // text reads exactly like a repository with nothing wrong in it.
    @Test func theScanItselfIsChecked() {
        // Written on one line, not as a `"""` literal: `RepositorySources` refuses to read one, and
        // nothing in this repository's own sources should be a shape its scans stop on.
        let handRolled = "var components = Calendar.current.dateComponents([.year], from: d)\n"
            + "components.timeZone = TimeZone.current"
        #expect(handRolledFireTimeBuilding(in: handRolled).count == 2)

        // The shape the two schedulers are now in, which must not be objected to.
        let shared = "let components = NotificationFireTime.dateComponents(for: fireDate)"
        #expect(handRolledFireTimeBuilding(in: shared).isEmpty)

        // Commented-out arithmetic is not arithmetic. This is the stripper's job, and it is asked to
        // show it does it here rather than being trusted to.
        #expect(handRolledFireTimeBuilding(in: "// components.timeZone = TimeZone.current").isEmpty)
    }

    // REQ-COM-014: the zone is attached, and it is the calendar's own.
    @Test func theFieldsCarryTheZoneTheyWereReadIn() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let components = NotificationFireTime.dateComponents(for: Date(timeIntervalSince1970: 1_700_000_000), calendar: calendar)

        #expect(components.timeZone == zone)
        // The instant the fields name is the instant asked for — which is what "the pair comes from one
        // place" buys. Read the fields back in their own zone and nothing has moved.
        #expect(calendar.date(from: components) == Date(timeIntervalSince1970: 1_700_000_000))
    }

    // REQ-COM-014: a zone named in the fields is not the machine's. Two calendars, two zones, one
    // instant: the wall-clock fields differ, the instant does not.
    @Test func aDifferentZoneNamesTheSameInstant() throws {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))

        let inTokyo = NotificationFireTime.dateComponents(for: instant, calendar: tokyo)
        let inUTC = NotificationFireTime.dateComponents(for: instant, calendar: utc)

        #expect(inTokyo.hour != inUTC.hour)
        #expect(tokyo.date(from: inTokyo) == utc.date(from: inUTC))
    }

    // The fields matched are down to the second and stop there: a fire time part-way into a minute
    // fires then, not at the top of the minute, and nothing finer is asked of the trigger. The
    // fraction of a second is dropped, which is what `UNCalendarNotificationTrigger` can act on.
    @Test func theFieldsGoDownToTheSecondAndNoFurther() throws {
        #expect(NotificationFireTime.matchedComponents == [.year, .month, .day, .hour, .minute, .second])

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let components = NotificationFireTime.dateComponents(
            for: Date(timeIntervalSince1970: 1_700_000_030.4), calendar: calendar
        )

        // 1_700_000_030.4 is 2023-11-14 22:13:50.4 UTC.
        #expect(components.second == 50)
        #expect(components.minute == 13)
        #expect(components.nanosecond == nil)
    }

    // **Both devices, one answer.** The two targets cannot be linked here, so what is checked is the
    // thing the scan above pins them to: for one instant, one function, one set of fields — there is no
    // per-device branch inside it to give the Mac and the iPhone different answers.
    @Test func theAnswerDoesNotDependOnWhoIsAsking() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let instant = Date(timeIntervalSince1970: 1_711_846_800)

        let once = NotificationFireTime.dateComponents(for: instant, calendar: calendar)
        let again = NotificationFireTime.dateComponents(for: instant, calendar: calendar)

        #expect(once == again)
        #expect(once.timeZone == calendar.timeZone)
    }
}
