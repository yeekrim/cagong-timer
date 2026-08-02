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

// MARK: - 내 신원 · 친구

/// 나를 가리키는 신원. **계정도 비밀번호도 없다.**
///
/// 설치할 때 기기마다 UUID를 하나 만들어 그게 곧 나다. 친구는 내 초대 코드로만
/// 나를 찾을 수 있어서, 이름이 겹쳐도 엉뚱한 사람이 걸리지 않는다.
struct Profile: Codable, Sendable {
    /// 서버에서 나를 식별하는 열쇠. 한 번 만들면 안 바뀐다.
    var id: UUID
    /// 친구에게 보이는 이름. 비워두면 친구 목록에서 "이름 없음"으로 뜬다.
    var name: String
    /// 친구가 나를 등록할 때 부르는 코드. 헷갈리는 글자(0/O, 1/I/L)는 뺀다.
    var code: String

    init(id: UUID = UUID(), name: String = "", code: String = Profile.newCode()) {
        self.id = id
        self.name = name
        self.code = code
    }

    enum CodingKeys: String, CodingKey { case id, name, code }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 없으면 지금 만든다 — 신원은 이 파일을 처음 읽는 순간 태어난다.
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? Profile.newCode()
    }

    /// 6자리 초대 코드. 헷갈리는 글자를 빼서 불러주기 쉽게 한다.
    static func newCode() -> String {
        let alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"   // 0 O 1 I L 제외
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}

/// 등록해 둔 친구 한 명. 서버가 진실이고, 이건 오프라인에서도 이름을 띄우려는 캐시다.
struct Friend: Codable, Sendable, Identifiable, Hashable {
    var id: UUID          // 친구의 Profile.id
    var name: String
    var code: String

    init(id: UUID, name: String, code: String) {
        self.id = id
        self.name = name
        self.code = code
    }
}

// MARK: - 친구 현재 상태 (presence)

/// 지금 무엇을 하고 있는지. 서버에 한 줄로 올려두고 친구가 읽어간다.
///
/// 이벤트(started/finished…)가 "방금 벌어진 순간"이라면, presence는 "지금 이 상태"다.
/// 친구 탭은 순간이 아니라 현재를 보여줘야 하므로 이게 따로 필요하다.
enum PresenceState: String, Codable, Sendable {
    case studying   // 재는 중
    case resting    // 멈췄지만 아직 안 끝냄
    case finished   // 오늘 공부 끝(Zzz)
    case idle       // 오늘 아직 시작 안 함
}

/// 서버에 올리는 현재 상태 스냅샷.
struct Presence: Codable, Sendable {
    var state: PresenceState
    var dayKey: String
    var seconds: TimeInterval
    var goalMinutes: Int
    var updatedAt: Date

    init(state: PresenceState, dayKey: String, seconds: TimeInterval,
         goalMinutes: Int, updatedAt: Date = Date()) {
        self.state = state
        self.dayKey = dayKey
        self.seconds = seconds
        self.goalMinutes = goalMinutes
        self.updatedAt = updatedAt
    }
}

/// 친구 탭에 실제로 그릴 상태. presence를 "보는 사람 기준"으로 해석한 결과다.
///
/// - 재는 중인데 갱신이 끊긴 지 오래면 → 앱을 닫은 것이니 `away`
/// - 마지막 활동이 어제였으면 → 오늘은 아직 `idle`
enum FriendActivity: String {
    case studying, away, resting, finished, idle

    var label: String {
        switch self {
        case .studying: return "공부 중"
        case .away:     return "잠시 자리 비움"
        case .resting:  return "휴식 중"
        case .finished: return "오늘 공부 끝"
        case .idle:     return "아직 시작 전"
        }
    }

    /// presence를 지금·오늘 기준으로 풀어, 화면에 쓸 상태와 시간을 낸다.
    ///
    /// 재는 중이면 마지막 갱신 이후 흐른 만큼을 더해 초를 이어 준다(대략 실시간).
    /// 단 갱신이 `awayAfter`보다 오래 끊겼으면 이어주지 않고 `away`로 본다.
    static func resolve(
        _ p: Presence?,
        now: Date = Date(),
        today: String,
        awayAfter: TimeInterval = 90
    ) -> (activity: FriendActivity, seconds: TimeInterval) {
        guard let p else { return (.idle, 0) }

        if p.state == .studying {
            let gap = now.timeIntervalSince(p.updatedAt)
            if gap > awayAfter { return (.away, p.seconds) }
            return (.studying, p.seconds + max(0, gap))
        }

        // 마지막 활동이 오늘이 아니면 오늘은 아직 시작 전이다.
        guard p.dayKey == today else { return (.idle, 0) }
        return (FriendActivity(rawValue: p.state.rawValue) ?? .idle, p.seconds)
    }
}

/// 친구 탭 한 줄. 친구 + 해석된 상태.
struct FriendStatus: Identifiable, Sendable {
    let friend: Friend
    let activity: FriendActivity
    /// `anchoredAt` 시점의 누적 시간. 공부 중이면 화면에서 이후 흐른 만큼을 더한다.
    let seconds: TimeInterval
    let goalMinutes: Int
    /// `seconds`를 잰 시각. 폴링 사이에도 초가 흐르게 하는 기준점.
    let anchoredAt: Date

    var id: UUID { friend.id }

    /// 지금 이 순간 보여줄 시간. 공부 중이면 기준점 이후 흐른 만큼을 이어 붙인다.
    func liveSeconds(at now: Date) -> TimeInterval {
        guard activity == .studying else { return seconds }
        return seconds + max(0, now.timeIntervalSince(anchoredAt))
    }

    func progress(at now: Date) -> Double {
        goalMinutes > 0 ? min(1, liveSeconds(at: now) / Double(goalMinutes * 60)) : 0
    }
}

// MARK: - 저장 파일 전체

/// 저장 파일은 통째로 값 타입이다.
/// 그래서 메인 스레드에서 싸게 복사해 백그라운드로 넘겨 인코딩할 수 있다.
struct AppData: Codable, Sendable {
    var version: Int
    var settings: AppSettings
    var days: [String: DayRecord]
    /// 나. 파일을 처음 읽는 순간 만들어진다.
    var profile: Profile
    /// 등록한 친구들의 캐시.
    var friends: [Friend]

    init(version: Int = 2,
         settings: AppSettings = AppSettings(),
         days: [String: DayRecord] = [:],
         profile: Profile = Profile(),
         friends: [Friend] = []) {
        self.version = version
        self.settings = settings
        self.days = days
        self.profile = profile
        self.friends = friends
    }

    enum CodingKeys: String, CodingKey {
        case version, settings, days, active, profile, friends
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        days = try c.decodeIfPresent([String: DayRecord].self, forKey: .days) ?? [:]
        // 신원은 나중에 붙었다. 옛 파일에는 없으므로 여기서 새로 만든다.
        profile = try c.decodeIfPresent(Profile.self, forKey: .profile) ?? Profile()
        friends = try c.decodeIfPresent([Friend].self, forKey: .friends) ?? []

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
        try c.encode(profile, forKey: .profile)
        try c.encode(friends, forKey: .friends)
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
