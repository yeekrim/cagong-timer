import Foundation

// MARK: - 날짜 키

/// 하루를 식별하는 키. 로컬 타임존 기준 "yyyy-MM-dd".
enum DateKey {
    static func string(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func today() -> String { string(from: Date()) }

    /// 그 달의 키 앞부분. "2026-07" — 날짜 키를 `hasPrefix`로 거를 때 쓴다.
    static func monthPrefix(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    static func yesterday() -> String {
        let d = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return string(from: d)
    }

    static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return Calendar.current.date(from: c)
    }
}

// MARK: - 한국어 날짜 표기

enum KoDate {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = format
        return f
    }

    private static let shortFormatter = formatter("M월 d일")
    private static let dayFormatter = formatter("M월 d일 (E)")
    private static let hourMinuteFormatter = formatter("HH:mm")

    /// "7월 30일"
    static func short(_ date: Date) -> String { shortFormatter.string(from: date) }

    /// "7월 31일 (금)"
    static func dayWithWeekday(_ date: Date) -> String { dayFormatter.string(from: date) }

    /// "14:32" — 기록을 되돌아볼 때는 초까지 필요 없다.
    static func hourMinute(_ date: Date) -> String { hourMinuteFormatter.string(from: date) }

    static let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]
}

// MARK: - 시간 표기

enum TimeFormat {
    /// "01:23:45"
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// "3시간 20분" / "20분" / "—"
    static func human(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return total == 0 ? "—" : "\(total)초" }
        let h = total / 3600, m = (total % 3600) / 60
        if h == 0 { return "\(m)분" }
        if m == 0 { return "\(h)시간" }
        return "\(h)시간 \(m)분"
    }

    /// 목표 시간 표기. "2시간" / "1시간 30분" / "0시간 30분" — 0시간도 그대로 쓴다.
    static func goal(minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60)시간" : "\(minutes / 60)시간 \(minutes % 60)분"
    }

    /// 먼슬리 셀에 들어가는 짧은 표기. "3h20" / "45m"
    static func compact(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }
}
