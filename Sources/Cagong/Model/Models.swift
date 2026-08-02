import Foundation

// MARK: - 날짜 키

/// 하루를 식별하는 키. 로컬 타임존 기준 "yyyy-MM-dd".
enum DateKey {
    static func string(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func today() -> String { string(from: Date()) }

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

// MARK: - 할 일

struct TodoItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var text: String
    var done: Bool
    /// 루틴으로 고정한 항목. 새 날이 시작될 때 체크가 풀린 채로 따라온다.
    /// 고정을 풀면 그날의 평범한 할 일로 남는다 — 지워지지 않는다.
    var pinned: Bool

    init(id: UUID = UUID(), text: String, done: Bool = false, pinned: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
        self.pinned = pinned
    }

    enum CodingKeys: String, CodingKey { case id, text, done, pinned }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    /// 새 날로 넘길 사본. 새 정체성으로 만들고 체크는 풀어 준다.
    var carriedToNewDay: TodoItem {
        TodoItem(text: text, done: false, pinned: true)
    }
}

// MARK: - 옛 형식 (마이그레이션 전용)

/// 예전에는 "진행 중인 하루"가 마감된 날들과 다른 타입으로 따로 있었다.
///
/// 그 구분이 애매함의 원인이었다 — 마감하지 않은 어제가 어디에도 속하지 않았다.
/// 지금은 모든 날이 `DayRecord` 하나로 동등하다. 이 타입은 옛 저장 파일을
/// 읽어 그날 기록으로 접어 넣기 위해서만 남아 있다.
private struct LegacyActiveSession: Decodable {
    var dateKey: String
    var accumulated: TimeInterval
    var todos: [TodoItem]

    enum CodingKeys: String, CodingKey { case dateKey, accumulated, todos }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dateKey = try c.decodeIfPresent(String.self, forKey: .dateKey) ?? DateKey.today()
        accumulated = try c.decodeIfPresent(TimeInterval.self, forKey: .accumulated) ?? 0
        todos = try c.decodeIfPresent([TodoItem].self, forKey: .todos) ?? []
    }
}

// MARK: - 공부 구간

/// 한 번 앉아서 공부한 구간. 시작을 누른 때부터 멈출 때까지.
///
/// **총합(`DayRecord.seconds`)과 별개다.** 총합은 그대로 두고 여기에는 "언제"만 담는다.
/// 총합을 이 배열에서 계산하도록 바꾸면 구간이 없는 옛 기록이 전부 0이 되고,
/// 이미 정확하게 도는 저장 경로를 다시 만들어야 한다. 얻는 것보다 잃는 게 크다.
struct StudySession: Codable, Sendable, Identifiable, Hashable {
    var id: UUID
    var start: Date
    /// 아직 재는 중이면 nil. **파일에는 nil로 남지 않는다** —
    /// 쓰기 직전에 그 시점으로 닫아서 내보낸다(`StudyStore.snapshotForWrite`).
    /// 그래서 앱이 갑자기 꺼져도 다음에 열 때 고칠 게 없다.
    var end: Date?

    init(id: UUID = UUID(), start: Date, end: Date? = nil) {
        self.id = id
        self.start = start
        self.end = end
    }

    enum CodingKeys: String, CodingKey { case id, start, end }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try c.decodeIfPresent(Date.self, forKey: .start) ?? Date()
        end = try c.decodeIfPresent(Date.self, forKey: .end)
    }

    /// 재는 중이면 지금까지의 길이
    func length(at now: Date = Date()) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }

    var isOpen: Bool { end == nil }
}

// MARK: - 하루 기록

/// 하루치 기록. **모든 날이 이 타입 하나로 동등하다.**
///
/// 진행 중이든 지난 날이든 구분이 없다. "지금 어느 날짜를 재고 있나"는
/// `StudyStore.measuringKey`가 따로 들고 있고, 저장하지 않는다.
struct DayRecord: Codable, Sendable {
    var seconds: TimeInterval
    var todos: [TodoItem]
    /// 하루를 마무리했다는 표시. **잠그지 않는다** — 다시 측정할 수 있다.
    var closed: Bool
    var endedAt: Date?
    /// 그날 앉았던 구간들. 언제 시작해 언제 접었는지가 여기 남는다.
    var sessions: [StudySession]
    /// 그날만의 목표. nil이면 마지막으로 쓴 기본 목표를 따른다.
    ///
    /// 목표는 날마다 다르다 — 시험 기간과 주말이 같을 리 없다. 그래서 설정에
    /// 하나로 박아두지 않고 그날 화면에서 바로 고친다.
    var goalMinutes: Int?

    init(seconds: TimeInterval = 0,
         todos: [TodoItem] = [],
         closed: Bool = false,
         endedAt: Date? = nil,
         goalMinutes: Int? = nil,
         sessions: [StudySession] = []) {
        self.seconds = seconds
        self.todos = todos
        self.closed = closed
        self.endedAt = endedAt
        self.goalMinutes = goalMinutes
        self.sessions = sessions
    }

    enum CodingKeys: String, CodingKey {
        case seconds, todos, closed, endedAt, goalMinutes, sessions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try c.decodeIfPresent(TimeInterval.self, forKey: .seconds) ?? 0
        todos = try c.decodeIfPresent([TodoItem].self, forKey: .todos) ?? []
        // 옛 파일에는 closed가 없다. 이미 마감된 기록이었으므로 true로 본다.
        closed = try c.decodeIfPresent(Bool.self, forKey: .closed) ?? true
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        goalMinutes = try c.decodeIfPresent(Int.self, forKey: .goalMinutes)
        // 구간 기록은 나중에 붙었다. 옛 기록에는 없고, 없는 채로 두면 된다 —
        // 총합은 `seconds`에 그대로 살아 있다.
        sessions = try c.decodeIfPresent([StudySession].self, forKey: .sessions) ?? []
    }

    var doneCount: Int { todos.filter(\.done).count }

    /// 그날 처음 시작한 시각
    var firstStart: Date? { sessions.map(\.start).min() }

    /// 그날 마지막으로 손 뗀 시각. Zzz를 눌렀으면 그 시각이 더 정확하다.
    var lastEnd: Date? {
        if let endedAt, closed { return endedAt }
        return sessions.compactMap(\.end).max()
    }
}

// MARK: - 설정

/// 설정은 앞으로 계속 늘어난다(BGM 볼륨, 알림 등).
/// 모든 키를 `decodeIfPresent`로 읽으므로 필드를 추가해도 기존 저장 파일이 깨지지 않는다.
struct AppSettings: Codable, Sendable {
    var themeID: ThemeID
    /// 새 날에 적용될 기본 목표. 날짜별로 고치면 이 값도 같이 따라간다 —
    /// 한 번 정해두면 다음 날부터는 손댈 일이 없다.
    var dailyGoalMinutes: Int
    var drinkID: DrinkID
    /// 사진 테마에서 고른 장면. nil이면 목록의 첫 장면.
    var photoSceneID: String?

    init(themeID: ThemeID = .photoCafe,
         dailyGoalMinutes: Int = 240,
         drinkID: DrinkID = .americano,
         photoSceneID: String? = nil) {
        self.themeID = themeID
        self.dailyGoalMinutes = dailyGoalMinutes
        self.drinkID = drinkID
        self.photoSceneID = photoSceneID
    }

    enum CodingKeys: String, CodingKey {
        case themeID, dailyGoalMinutes, drinkID, photoSceneID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // 열거형은 원시 문자열로 읽어서 직접 되돌린다.
        // 목록에서 빠진 값(예: 없어진 음료)을 만나면 열거형 디코딩은 예외를 던지고,
        // 그러면 AppData 디코딩까지 실패해서 기록 전체가 초기값으로 밀린다.
        let rawTheme = try c.decodeIfPresent(String.self, forKey: .themeID)
        themeID = rawTheme.flatMap(ThemeID.init(rawValue:)) ?? .photoCafe

        let rawDrink = try c.decodeIfPresent(String.self, forKey: .drinkID)
        drinkID = rawDrink.flatMap(DrinkID.init(rawValue:)) ?? .americano

        dailyGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyGoalMinutes) ?? 240
        photoSceneID = try c.decodeIfPresent(String.self, forKey: .photoSceneID)
    }
}

// MARK: - 저장 파일 전체

/// 저장 파일은 통째로 값 타입이다.
/// 그래서 메인 스레드에서 싸게 복사해 백그라운드로 넘겨 인코딩할 수 있다.
struct AppData: Codable, Sendable {
    var version: Int
    var settings: AppSettings
    var days: [String: DayRecord]

    init(version: Int = 2,
         settings: AppSettings = AppSettings(),
         days: [String: DayRecord] = [:]) {
        self.version = version
        self.settings = settings
        self.days = days
    }

    enum CodingKeys: String, CodingKey { case version, settings, days, active }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        days = try c.decodeIfPresent([String: DayRecord].self, forKey: .days) ?? [:]

        // 옛 형식 이관: 따로 있던 "진행 중인 하루"를 그날 기록으로 접어 넣는다.
        // try? 가 옵셔널을 한 겹 벗기므로 여기서 바로 값이 나온다.
        if let legacy = try? c.decodeIfPresent(LegacyActiveSession.self, forKey: .active) {
            var day = days[legacy.dateKey] ?? DayRecord()
            day.seconds += legacy.accumulated
            day.todos.append(contentsOf: legacy.todos)
            day.closed = false          // 마감하지 않았던 날이다
            days[legacy.dateKey] = day
        }

        version = max(version, 2)
    }

    /// `active`는 옛 파일을 읽기 위한 키일 뿐이라 쓰지 않는다.
    /// 프로퍼티가 없는 키가 `CodingKeys`에 있으면 인코딩이 자동 합성되지 않으므로 직접 쓴다.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(settings, forKey: .settings)
        try c.encode(days, forKey: .days)
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

    private static let fullFormatter = formatter("M월 d일 EEEE")
    private static let shortFormatter = formatter("M월 d일")
    private static let dayFormatter = formatter("M월 d일 (E)")
    private static let clockFormatter = formatter("HH:mm:ss")
    private static let hourMinuteFormatter = formatter("HH:mm")

    /// "7월 30일 목요일"
    static func full(_ date: Date) -> String { fullFormatter.string(from: date) }

    /// "7월 30일"
    static func short(_ date: Date) -> String { shortFormatter.string(from: date) }

    /// "7월 31일 (금)"
    static func dayWithWeekday(_ date: Date) -> String { dayFormatter.string(from: date) }

    /// "14:32:07"
    static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }

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

    /// 먼슬리 셀에 들어가는 짧은 표기. "3h20" / "45m"
    static func compact(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h\(m)"
    }
}
