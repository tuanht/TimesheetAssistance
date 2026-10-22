import Foundation

public struct ScheduleItem: Sendable {
    public var entryId: UUID
    public var hintMinutes: Int?
    public var estimatedMinutes: Int
    public var fixed: (start: ClockTime, end: ClockTime)?

    public init(entryId: UUID, hintMinutes: Int?, estimatedMinutes: Int, fixed: (start: ClockTime, end: ClockTime)?) {
        self.entryId = entryId
        self.hintMinutes = hintMinutes
        self.estimatedMinutes = estimatedMinutes
        self.fixed = fixed
    }
}

public struct ScheduledSlot: Equatable, Sendable {
    public var entryId: UUID
    public var start: ClockTime
    public var end: ClockTime

    public init(entryId: UUID, start: ClockTime, end: ClockTime) {
        self.entryId = entryId
        self.start = start
        self.end = end
    }
}

/// Lays a day's entries onto the clock. The LLM only estimates relative size; time comes from here.
/// Never drops an item: problems (overbooking, meetings in lunch) are left for the validator to flag.
public enum Scheduler {
    public static func schedule(_ items: [ScheduleItem], hours: WorkingHours) -> [ScheduledSlot] {
        let fixedRanges = items.compactMap { $0.fixed.map { $0.start.minutes..<max($0.start.minutes, $0.end.minutes) } }
        let segments = freeSegments(hours: hours, minus: fixedRanges)
        let flexible = items.filter { $0.fixed == nil }
        let durations = allocate(flexible, free: segments.reduce(0) { $0 + $1.count }, unit: max(1, hours.roundingMinutes))

        var slots = items.compactMap { item in
            item.fixed.map { ScheduledSlot(entryId: item.entryId, start: $0.start, end: $0.end) }
        }

        // Overflow starts after the working day and after any fixed slot, so it never overlaps one.
        let overflowStart = max(hours.end.minutes, fixedRanges.map(\.upperBound).max() ?? 0)
        var segmentIndex = 0
        var cursor = segments.first?.lowerBound ?? overflowStart
        for (item, duration) in zip(flexible, durations) {
            var remaining = duration
            while remaining > 0 {
                let take: Int
                if segmentIndex < segments.count {
                    let available = segments[segmentIndex].upperBound - cursor
                    take = min(remaining, available)
                } else {
                    take = remaining
                }
                slots.append(ScheduledSlot(entryId: item.entryId, start: ClockTime(0, cursor), end: ClockTime(0, cursor + take)))
                remaining -= take
                cursor += take
                if segmentIndex < segments.count, cursor == segments[segmentIndex].upperBound {
                    segmentIndex += 1
                    cursor = segmentIndex < segments.count ? segments[segmentIndex].lowerBound : overflowStart
                }
            }
        }

        return slots.enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
    }

    /// Working segments around lunch, with every fixed interval cut out. Non-empty, ascending.
    static func freeSegments(hours: WorkingHours, minus fixed: [Range<Int>]) -> [Range<Int>] {
        var segments: [Range<Int>]
        if hours.lunchStart == hours.lunchEnd {
            segments = [hours.start.minutes..<max(hours.start.minutes, hours.end.minutes)]
        } else {
            segments = [
                hours.start.minutes..<max(hours.start.minutes, hours.lunchStart.minutes),
                hours.lunchEnd.minutes..<max(hours.lunchEnd.minutes, hours.end.minutes),
            ]
        }
        for cut in fixed where !cut.isEmpty {
            segments = segments.flatMap { seg -> [Range<Int>] in
                guard seg.overlaps(cut) else { return [seg] }
                return [seg.lowerBound..<max(seg.lowerBound, cut.lowerBound),
                        min(cut.upperBound, seg.upperBound)..<seg.upperBound]
            }
        }
        return segments.filter { !$0.isEmpty }
    }

    /// Minutes per flexible item: hints exactly; unhinted items share the rest by estimate, on the rounding grid.
    static func allocate(_ items: [ScheduleItem], free: Int, unit: Int) -> [Int] {
        // A non-positive hint would produce no slot and drop the item, so it counts as unhinted.
        let hints = items.map { $0.hintMinutes.flatMap { $0 > 0 ? $0 : nil } }
        let share = free - hints.reduce(0) { $0 + ($1 ?? 0) }
        let unhinted = items.indices.filter { hints[$0] == nil }
        let weightTotal = unhinted.reduce(0) { $0 + max(1, items[$1].estimatedMinutes) }

        var result = hints.map { $0 ?? 0 }
        var given = 0
        for (n, i) in unhinted.enumerated() {
            let raw = Double(max(0, share)) * Double(max(1, items[i].estimatedMinutes)) / Double(weightTotal)
            var minutes = max(unit, Int((raw / Double(unit)).rounded()) * unit)
            if n == unhinted.count - 1 {
                // Remainder lands here so the day totals F; keep the one-unit minimum even if it overflows.
                minutes = max(unit, share - given)
            }
            result[i] = minutes
            given += minutes
        }
        return result
    }
}
