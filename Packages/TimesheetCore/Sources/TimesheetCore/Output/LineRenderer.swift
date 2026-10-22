import Foundation

public enum LineRenderer {
    public static func render(_ lines: [TimesheetLine], day: Date, template: TemplateSettings) -> String {
        let dateText = formatter(template.dateFormat).string(from: day)
        let sorted = lines.enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
        return sorted
            .map { line in
                template.fields
                    .map { value(of: $0, line: line, dateText: dateText, template: template) }
                    .joined(separator: template.separator)
            }
            .joined(separator: "\n")
    }

    private static func value(
        of field: TemplateField, line: TimesheetLine, dateText: String, template: TemplateSettings
    ) -> String {
        switch field {
        case .date: dateText
        case .start: clean(time(line.start, template.timeFormat), template)
        case .end: clean(time(line.end, template.timeFormat), template)
        case .description:
            clean(line.description, template)
        case .ticket:
            clean(line.ticket.flatMap { $0.isEmpty ? nil : $0 } ?? template.emptyTicketPlaceholder, template)
        case .activityType: clean(line.activityType, template)
        case .classification: clean(line.classification, template)
        }
    }

    private static func clean(_ s: String, _ template: TemplateSettings) -> String {
        let one = collapse(s)
        let sep = template.separator
        let core = sep.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return one }
        // Only the exact separator is replaced; its padding is kept so "API | DB" becomes "API / DB".
        let leading = sep.prefix { $0 == " " || $0 == "\t" }
        let trailing = String(sep.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
        return one.replacingOccurrences(of: sep, with: leading + template.separatorSubstitute + trailing)
    }

    private static func collapse(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func time(_ t: ClockTime, _ format: String) -> String {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1
        c.hour = t.minutes / 60; c.minute = t.minutes % 60
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        let f = formatter(format)
        f.timeZone = .gmt
        return f.string(from: cal.date(from: c) ?? Date(timeIntervalSince1970: 0))
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
