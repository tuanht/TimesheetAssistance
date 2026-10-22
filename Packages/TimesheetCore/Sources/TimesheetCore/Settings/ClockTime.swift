import Foundation

public struct ClockTime: Codable, Hashable, Comparable, Sendable {
    public var minutes: Int

    public init(_ h: Int, _ m: Int) {
        minutes = h * 60 + m
    }

    public init?(_ hhmm: String) {
        let parts = hhmm.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m)
        else { return nil }
        self.init(h, m)
    }

    public var hhmm: String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// Nearest multiple of `step`; ties round up.
    public func rounded(to step: Int) -> ClockTime {
        guard step > 0 else { return self }
        let snapped = (minutes + step / 2) / step * step
        return ClockTime(0, snapped)
    }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutes < rhs.minutes
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let t = ClockTime(s) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "Invalid HH:mm: \(s)"))
        }
        self = t
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hhmm)
    }
}
