import Foundation

/// The Compile footer's time total, e.g. "Total 7h 30m of 7h 30m".
public enum TotalText {
    public static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(rest)m"
        }
    }

    public static func total(_ minutes: Int, of working: Int) -> String {
        "Total \(duration(minutes)) of \(duration(working))"
    }
}
