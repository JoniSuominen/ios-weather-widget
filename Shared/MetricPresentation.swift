import Foundation

/// Age of the oldest displayed data in whole minutes. Widgets step this label
/// with one timeline entry per minute instead of a per-second relative clock.
enum UpdatedLabel {
    static func minutes(since date: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(date) / 60))
    }

    /// "0m", "12m", "3h", "2d".
    static func short(since date: Date, now: Date) -> String {
        let elapsed = Self.minutes(since: date, now: now)
        if elapsed < 60 { return "\(elapsed)m" }
        if elapsed < 24 * 60 { return "\(elapsed / 60)h" }
        return "\(elapsed / (24 * 60))d"
    }

    /// "Updated 0 min ago", "Updated 3 h ago".
    static func long(since date: Date, now: Date) -> String {
        let elapsed = Self.minutes(since: date, now: now)
        if elapsed < 60 { return "Updated \(elapsed) min ago" }
        if elapsed < 24 * 60 { return "Updated \(elapsed / 60) h ago" }
        return "Updated \(elapsed / (24 * 60)) d ago"
    }
}

/// When an event happens, computed at display time so it never goes stale.
enum EventTiming {
    /// "14:30" today, "Tomorrow 09:00", or "Thu 09:00" later in the week.
    static func startText(_ start: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = start.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(start, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(start, inSameDayAs: tomorrow) {
            return "Tomorrow \(time)"
        }
        return "\(start.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }

    static func isOngoing(start: Date, end: Date?, now: Date) -> Bool {
        start <= now && (end.map { now < $0 } ?? false)
    }

    /// "in 25m", "in 3h 5m", "in 2d", or "until 15:00" for an event in progress.
    static func relativeText(start: Date, end: Date?, now: Date) -> String {
        if isOngoing(start: start, end: end, now: now), let end {
            return "until \(end.formatted(date: .omitted, time: .shortened))"
        }
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "in \(minutes)m" }
        if minutes < 24 * 60 {
            let remainder = minutes % 60
            return remainder == 0 ? "in \(minutes / 60)h" : "in \(minutes / 60)h \(remainder)m"
        }
        return "in \(minutes / (24 * 60))d"
    }

    /// The single label for a narrow tile: a countdown within the hour,
    /// otherwise the start time.
    static func compactText(start: Date, end: Date?, now: Date) -> String {
        if isOngoing(start: start, end: end, now: now) { return "Now" }
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes > 0 && minutes < 60 { return "in \(minutes)m" }
        return startText(start, now: now)
    }
}

/// WHO UV index categories.
enum UVLevel: String {
    case low
    case moderate
    case high
    case veryHigh
    case extreme

    init(index: Double) {
        switch index {
        case ..<2.5: self = .low
        case ..<5.5: self = .moderate
        case ..<7.5: self = .high
        case ..<10.5: self = .veryHigh
        default: self = .extreme
        }
    }

    var label: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .veryHigh: return "Very high"
        case .extreme: return "Extreme"
        }
    }

    var tint: String {
        switch self {
        case .low: return "green"
        case .moderate: return "yellow"
        case .high: return "orange"
        case .veryHigh: return "red"
        case .extreme: return "violet"
        }
    }
}

/// WMO weather interpretation codes used by Open-Meteo.
enum WeatherCode {
    static func symbol(for code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0, 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63, 65: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func text(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Unknown"
        }
    }
}

enum WeatherFormat {
    private static let temperatureFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.unitStyle = .short
        // Converts to the person's preferred scale but prints only "14°".
        formatter.unitOptions = .temperatureWithoutUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter
    }()

    static func temperature(_ celsius: Double) -> String {
        // Avoid "-0°" for values that round to zero.
        let value = abs(celsius) < 0.5 ? 0 : celsius
        return temperatureFormatter.string(from: Measurement(value: value, unit: UnitTemperature.celsius))
    }

    static func precipitation(_ millimeters: Double, locale: Locale = .current) -> String {
        if locale.measurementSystem == .us {
            let inches = millimeters / 25.4
            return "\(inches.formatted(.number.precision(.fractionLength(inches < 1 ? 2 : 1)))) in"
        }
        let digits = millimeters < 10 ? 1 : 0
        return "\(millimeters.formatted(.number.precision(.fractionLength(digits)))) mm"
    }
}
