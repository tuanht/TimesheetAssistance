import Foundation
import Testing
@testable import TimesheetCore

struct SchedulerTests {
    let hours = WorkingHours.default

    func item(_ estimate: Int = 1, hint: Int? = nil, fixed: (ClockTime, ClockTime)? = nil) -> ScheduleItem {
        ScheduleItem(entryId: UUID(), hintMinutes: hint, estimatedMinutes: estimate,
                     fixed: fixed.map { (start: $0.0, end: $0.1) })
    }

    func minutes(of id: UUID, in slots: [ScheduledSlot]) -> Int {
        slots.filter { $0.entryId == id }.reduce(0) { $0 + $1.end.minutes - $1.start.minutes }
    }

    @Test func fillsDayExactlyWithNoGaps() {
        let items = [item(1), item(1), item(2)]
        let slots = Scheduler.schedule(items, hours: hours)

        let morning = slots.filter { $0.end <= ClockTime(12, 0) }
        let afternoon = slots.filter { $0.start >= ClockTime(13, 0) }
        #expect(morning.count + afternoon.count == slots.count)
        #expect(morning.first?.start == ClockTime(9, 0))
        #expect(morning.last?.end == ClockTime(12, 0))
        #expect(afternoon.first?.start == ClockTime(13, 0))
        #expect(afternoon.last?.end == ClockTime(17, 30))
        for run in [morning, afternoon] {
            for (a, b) in zip(run, run.dropFirst()) { #expect(a.end == b.start) }
        }
        #expect(slots.reduce(0) { $0 + $1.end.minutes - $1.start.minutes } == 450)
        for i in items { #expect(minutes(of: i.entryId, in: slots) > 0) }
    }

    @Test func biggerEstimateGetsMoreTime() {
        let small = item(1), big = item(2)
        let slots = Scheduler.schedule([small, big], hours: hours)
        #expect(minutes(of: big.entryId, in: slots) > minutes(of: small.entryId, in: slots))
    }

    @Test func hintIsHonouredExactly() {
        let hinted = item(5, hint: 120), a = item(1), b = item(1)
        let slots = Scheduler.schedule([a, hinted, b], hours: hours)
        #expect(minutes(of: hinted.entryId, in: slots) == 120)
        #expect(minutes(of: a.entryId, in: slots) + minutes(of: b.entryId, in: slots) == 330)
    }

    @Test func fixedMeetingKeepsSlot() {
        let meeting = item(fixed: (ClockTime(10, 0), ClockTime(10, 30)))
        let a = item(1), b = item(1)
        let slots = Scheduler.schedule([a, meeting, b], hours: hours)

        #expect(slots.filter { $0.entryId == meeting.entryId }
            == [ScheduledSlot(entryId: meeting.entryId, start: ClockTime(10, 0), end: ClockTime(10, 30))])
        for s in slots where s.entryId != meeting.entryId {
            #expect(s.end <= ClockTime(10, 0) || s.start >= ClockTime(10, 30))
        }
        #expect(minutes(of: a.entryId, in: slots) + minutes(of: b.entryId, in: slots) == 420)
    }

    @Test func itemCrossingLunchIsSplit() {
        let first = item(hint: 150), crossing = item(hint: 60), rest = item(1)
        let slots = Scheduler.schedule([first, crossing, rest], hours: hours)
        let parts = slots.filter { $0.entryId == crossing.entryId }
        #expect(parts == [
            ScheduledSlot(entryId: crossing.entryId, start: ClockTime(11, 30), end: ClockTime(12, 0)),
            ScheduledSlot(entryId: crossing.entryId, start: ClockTime(13, 0), end: ClockTime(13, 30)),
        ])
    }

    @Test func overbookedHintsSpillPastEnd() {
        let a = item(hint: 300), b = item(hint: 300), c = item(1)
        let slots = Scheduler.schedule([a, b, c], hours: hours)
        #expect(minutes(of: a.entryId, in: slots) == 300)
        #expect(minutes(of: b.entryId, in: slots) == 300)
        #expect(minutes(of: c.entryId, in: slots) >= hours.roundingMinutes)
        #expect(slots.last!.end > ClockTime(17, 30))
        for (x, y) in zip(slots, slots.dropFirst()) { #expect(x.end <= y.start) }
    }

    @Test func fixedMeetingInLunchIsKept() {
        let meeting = item(fixed: (ClockTime(12, 15), ClockTime(12, 45)))
        let slots = Scheduler.schedule([item(1), meeting], hours: hours)
        #expect(slots.contains(
            ScheduledSlot(entryId: meeting.entryId, start: ClockTime(12, 15), end: ClockTime(12, 45))))
    }

    @Test func allSlotsOnRoundingGrid() {
        let items = [item(3), item(1), item(fixed: (ClockTime(14, 0), ClockTime(15, 0))), item(2), item(7)]
        let slots = Scheduler.schedule(items, hours: hours)
        for s in slots {
            #expect(s.start.minutes % 15 == 0)
            #expect(s.end.minutes % 15 == 0)
        }
    }

    @Test func outputSortedByStart() {
        let items = [item(1), item(fixed: (ClockTime(9, 0), ClockTime(9, 30))), item(2)]
        let slots = Scheduler.schedule(items, hours: hours)
        #expect(slots.map(\.start) == slots.map(\.start).sorted())
    }

    @Test func zeroHintIsNotDropped() {
        let zero = item(1, hint: 0)
        let slots = Scheduler.schedule([zero, item(1)], hours: hours)
        #expect(minutes(of: zero.entryId, in: slots) > 0)
    }

    @Test func emptyInputGivesNoSlots() {
        #expect(Scheduler.schedule([], hours: hours).isEmpty)
    }
}
