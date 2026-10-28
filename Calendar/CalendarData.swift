import Foundation

struct LunarDate: Equatable {
    let day: Int
    let month: Int
    let year: Int
    let isLeapMonth: Bool
}

/// Vietnamese lunisolar calendar using the UTC+7 civil-time convention.
/// Based on the new-moon / solar-longitude method commonly known as Hồ Ngọc Đức's algorithm.
enum VietnameseLunarCalendar {
    private static let timeZone = 7.0
    private static let epoch = 2415021.076998695

    static func date(from solarDate: Date) -> LunarDate? {
        var vietnam = Calendar(identifier: .gregorian)
        vietnam.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        let c = vietnam.dateComponents([.day, .month, .year], from: solarDate)
        guard let day = c.day, let month = c.month, let year = c.year,
              (1900...2100).contains(year) else { return nil }

        let dayNumber = julianDay(day: day, month: month, year: year)
        let k = Int(floor((Double(dayNumber) - epoch) / 29.530588853))
        var monthStart = newMoonDay(k + 1)
        if monthStart > dayNumber { monthStart = newMoonDay(k) }

        var a11 = lunarMonth11(year)
        var b11 = a11
        let lunarYear: Int
        if a11 >= monthStart {
            lunarYear = year
            a11 = lunarMonth11(year - 1)
        } else {
            lunarYear = year + 1
            b11 = lunarMonth11(year + 1)
        }

        let lunarDay = dayNumber - monthStart + 1
        let diff = Int(floor(Double(monthStart - a11) / 29.0))
        var lunarMonth = diff + 11
        var leap = false
        if b11 - a11 > 365 {
            let leapOffset = leapMonthOffset(a11)
            if diff >= leapOffset {
                lunarMonth = diff + 10
                leap = diff == leapOffset
            }
        }
        if lunarMonth > 12 { lunarMonth -= 12 }
        var adjustedYear = lunarYear
        if lunarMonth >= 11 && diff < 4 { adjustedYear -= 1 }
        return LunarDate(day: lunarDay, month: lunarMonth, year: adjustedYear, isLeapMonth: leap)
    }

    private static func julianDay(day: Int, month: Int, year: Int) -> Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        var jd = day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
        if jd < 2299161 { jd = day + (153 * m + 2) / 5 + 365 * y + y / 4 - 32083 }
        return jd
    }

    private static func newMoonDay(_ k: Int) -> Int {
        Int(floor(newMoon(k) + 0.5 + timeZone / 24.0))
    }

    private static func newMoon(_ k: Int) -> Double {
        let t = Double(k) / 1236.85
        let t2 = t * t
        let t3 = t2 * t
        let dr = Double.pi / 180
        var jd = 2415020.75933 + 29.53058868 * Double(k) + 0.0001178 * t2 - 0.000000155 * t3
        jd += 0.00033 * sin((166.56 + 132.87 * t - 0.009173 * t2) * dr)
        let m = 359.2242 + 29.10535608 * Double(k) - 0.0000333 * t2 - 0.00000347 * t3
        let mp = 306.0253 + 385.81691806 * Double(k) + 0.0107306 * t2 + 0.00001236 * t3
        let f = 21.2964 + 390.67050646 * Double(k) - 0.0016528 * t2 - 0.00000239 * t3
        var correction = (0.1734 - 0.000393 * t) * sin(m * dr) + 0.0021 * sin(2 * m * dr)
        correction -= 0.4068 * sin(mp * dr) + 0.0161 * sin(2 * mp * dr)
        correction -= 0.0004 * sin(3 * mp * dr)
        correction += 0.0104 * sin(2 * f * dr) - 0.0051 * sin((m + mp) * dr)
        correction -= 0.0074 * sin((m - mp) * dr) + 0.0004 * sin((2 * f + m) * dr)
        correction -= 0.0004 * sin((2 * f - m) * dr) - 0.0006 * sin((2 * f + mp) * dr)
        correction += 0.0010 * sin((2 * f - mp) * dr) + 0.0005 * sin((2 * mp + m) * dr)
        let deltaT: Double
        if t < -11 {
            deltaT = 0.001 + 0.000839 * t + 0.0002261 * t2 - 0.00000845 * t3 - 0.000000081 * t2 * t2
        } else {
            deltaT = -0.000278 + 0.000265 * t + 0.000262 * t2
        }
        jd += correction - deltaT
        return jd
    }

    private static func sunLongitude(_ dayNumber: Int) -> Double {
        let t = (Double(dayNumber) - 0.5 - timeZone / 24.0 - 2451545.0) / 36525.0
        let t2 = t * t
        let dr = Double.pi / 180
        let m = 357.52910 + 35999.05030 * t - 0.0001559 * t2 - 0.00000048 * t * t2
        let l0 = 280.46645 + 36000.76983 * t + 0.0003032 * t2
        var deltaL = (1.914600 - 0.004817 * t - 0.000014 * t2) * sin(dr * m)
        deltaL += (0.019993 - 0.000101 * t) * sin(2 * dr * m) + 0.000290 * sin(3 * dr * m)
        var longitude = (l0 + deltaL) * dr
        longitude -= 2 * Double.pi * floor(longitude / (2 * Double.pi))
        return longitude
    }

    private static func lunarMonth11(_ year: Int) -> Int {
        let off = julianDay(day: 31, month: 12, year: year) - 2415021
        let k = Int(floor(Double(off) / 29.530588853))
        var nm = newMoonDay(k)
        if Int(floor(sunLongitude(nm) / Double.pi * 6)) >= 9 { nm = newMoonDay(k - 1) }
        return nm
    }

    private static func leapMonthOffset(_ a11: Int) -> Int {
        let k = Int(floor(0.5 + Double(a11 - 2415021) / 29.530588853))
        var i = 1
        var last = Int(floor(sunLongitude(newMoonDay(k + i)) / Double.pi * 6))
        var arc = last
        repeat {
            last = arc
            i += 1
            arc = Int(floor(sunLongitude(newMoonDay(k + i)) / Double.pi * 6))
        } while arc != last && i < 14
        return i - 1
    }
}

struct CalendarNote: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var dateKey: String
    var title: String
    var details: String
    var reminder: Date?
}

enum CalendarDateKey {
    static let vietnamTimeZone = TimeZone(secondsFromGMT: 7 * 3600)!
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = vietnamTimeZone
        return c
    }
    static func string(from date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

enum VietnamHoliday {
    static func names(for date: Date) -> [String] {
        let c = CalendarDateKey.calendar.dateComponents([.day, .month], from: date)
        guard let d = c.day, let m = c.month else { return [] }
        var names: [String] = []
        switch (m, d) {
        case (1, 1): names.append("Tết Dương lịch")
        case (2, 14): names.append("Valentine")
        case (3, 8): names.append("Ngày Quốc tế Phụ nữ")
        case (4, 30): names.append("Ngày Giải phóng miền Nam")
        case (5, 1): names.append("Ngày Quốc tế Lao động")
        case (6, 1): names.append("Ngày Quốc tế Thiếu nhi")
        case (9, 2): names.append("Quốc khánh")
        case (10, 20): names.append("Ngày Phụ nữ Việt Nam")
        case (11, 20): names.append("Ngày Nhà giáo Việt Nam")
        case (12, 24): names.append("Đêm Giáng sinh")
        case (12, 25): names.append("Lễ Giáng sinh")
        default: break
        }
        if let lunar = VietnameseLunarCalendar.date(from: date) {
            if lunar.day == 1 && lunar.month == 1 { names.append("Tết Nguyên Đán") }
            if lunar.day == 10 && lunar.month == 3 { names.append("Giỗ Tổ Hùng Vương (10/3 âm lịch)") }
            if lunar.day == 15 && lunar.month == 4 { names.append("Lễ Phật Đản") }
            if lunar.day == 15 && lunar.month == 7 { names.append("Lễ Vu Lan") }
            if lunar.day == 15 && lunar.month == 8 { names.append("Tết Trung Thu") }
            if lunar.day == 23 && lunar.month == 12 { names.append("Ông Công Ông Táo") }
        }
        return names
    }
}
