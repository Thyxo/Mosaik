// Datoer til biblioteket (falske for puljen, ægte for kamerarullen) og dansk formatering.
import Foundation

enum Dates {
    static let locale = Locale(identifier: "da_DK")

    /// Datoer for alle pladser. De sidste `real.count` er de ægte (nyeste sidst); resten ligger før dem i klumper.
    static func make(count: Int, real: [Date], seed: UInt64) -> [Date] {
        var rng = SplitMix64(seed: seed ^ 0xDA7E)
        var out = [Date](repeating: Date(), count: count)
        let k = min(real.count, count)
        for j in 0..<k { out[count - 1 - j] = real[j] }
        var t = (k > 0 ? real[k - 1] : Date()).timeIntervalSince1970 - Double.random(in: 3600...86400 * 2, using: &rng)
        var left = 0
        for i in stride(from: count - 1 - k, through: 0, by: -1) {
            out[i] = Date(timeIntervalSince1970: t)
            if left <= 0 {
                left = Int.random(in: 1...14, using: &rng)
                t -= Double.random(in: 3600 * 6...86400 * 4, using: &rng)
                // dagtimer
                let cal = Calendar.current
                var c = cal.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: t))
                c.hour = Int.random(in: 9...20, using: &rng); c.minute = Int.random(in: 0...59, using: &rng)
                t = cal.date(from: c)?.timeIntervalSince1970 ?? t
            } else {
                left -= 1
                t -= Double.random(in: 15...1800, using: &rng)
            }
        }
        return out
    }

    static func number(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static func fmt(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(pattern)
        return f
    }
    private static let dayMonthYear = fmt("dMMMy")
    private static let monthYear = fmt("MMMMy")
    private static let dayMonth = fmt("dMMMM")
    private static let longDay = fmt("dMMMMy")
    private static let weekday = fmt("EEEE")
    private static let monthAbbr: DateFormatter = { let f = DateFormatter(); f.locale = locale; f.dateFormat = "MMM"; return f }()
    /// "Okt." / "Maj"
    static func monthShort(_ d: Date) -> String { monthAbbr.string(from: d).capitalizedFirst }
    private static let time: DateFormatter = { let f = DateFormatter(); f.locale = locale; f.dateFormat = "HH.mm"; return f }()

    /// Undertitel i biblioteket mens man scroller
    static func header(_ d: Date, fine: Bool) -> String {
        fine ? dayMonthYear.string(from: d) : monthYear.string(from: d).capitalizedFirst
    }

    /// Titel og klokkeslæt i fremviseren
    static func viewer(_ d: Date) -> (String, String) {
        let cal = Calendar.current
        let title: String
        if cal.isDateInToday(d) { title = "I dag" }
        else if cal.isDateInYesterday(d) { title = "I går" }
        else if let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day, days < 7 {
            title = weekday.string(from: d).capitalizedFirst
        } else if cal.isDate(d, equalTo: Date(), toGranularity: .year) { title = dayMonth.string(from: d) }
        else { title = longDay.string(from: d) }
        return (title, time.string(from: d))
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
