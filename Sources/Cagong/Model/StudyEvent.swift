import Foundation

/// 공부하다 벌어진 일. 알림으로 알릴 만한 순간들.
///
/// 지금은 내 목표 달성만 로컬 알림으로 쓰지만, 친구 기능이 붙으면 **같은 이벤트를**
/// 그대로 서버로 흘려보낸다. 그래서 "누구에게 보낼지"는 여기 없다 — 무슨 일이
/// 있었는지만 담는다.
enum StudyEventKind: String, Codable, Sendable, CaseIterable {
    /// 그날 처음 앉았다
    case started
    /// 쉬었다가 다시 앉았다
    case resumed
    /// 목표의 절반을 넘겼다
    case halfGoal
    /// 목표를 채웠다
    case fullGoal
    /// 오늘 공부를 마쳤다 (Zzz)
    case finished

    /// 내 화면에 로컬 알림으로 띄울 이벤트인지.
    ///
    /// 시작·재개·마무리는 내가 방금 누른 것이라 나에게 알릴 이유가 없다.
    /// 목표 절반·전부는 재는 도중 저절로 넘어가는 순간이라 나도 알고 싶다.
    var notifiesSelf: Bool {
        switch self {
        case .halfGoal, .fullGoal: return true
        case .started, .resumed, .finished: return false
        }
    }

    /// 친구에게 보낼 이벤트인지.
    ///
    /// **다섯 순간 전부 친구에게 간다** — 시작·재개·마무리는 내가 눌러도 친구에게는
    /// 핵심 신호이고, 목표 절반·전부는 나와 친구가 **둘 다** 받는다.
    /// 서버가 붙으면 이 플래그가 켜진 이벤트만 밖으로 내보낸다.
    var notifiesFriends: Bool { true }
}

/// 이벤트 하나. 언제, 어느 날 기록에서, 그때 얼마나 했는지까지 담는다.
///
/// 친구 쪽에서 "3시간 12분째 하는 중"처럼 보여주려면 시각만으로는 부족해서
/// 그 순간의 누적 시간과 목표를 같이 싣는다.
struct StudyEvent: Codable, Sendable, Identifiable, Hashable {
    var id: UUID
    var kind: StudyEventKind
    var at: Date
    /// 어느 날 기록에서 벌어진 일인지
    var dayKey: String
    var seconds: TimeInterval
    var goalMinutes: Int

    init(
        id: UUID = UUID(),
        kind: StudyEventKind,
        at: Date = Date(),
        dayKey: String,
        seconds: TimeInterval,
        goalMinutes: Int
    ) {
        self.id = id
        self.kind = kind
        self.at = at
        self.dayKey = dayKey
        self.seconds = seconds
        self.goalMinutes = goalMinutes
    }

    /// 나에게 띄울 알림 문구. 친구용 문구는 이름이 필요하므로 따로 만든다.
    var selfTitle: String {
        switch kind {
        case .halfGoal: return "절반 왔어요"
        case .fullGoal: return "목표 달성"
        case .started: return "공부 시작"
        case .resumed: return "다시 시작"
        case .finished: return "오늘 공부 끝"
        }
    }

    var selfBody: String {
        let done = TimeFormat.human(seconds)
        switch kind {
        case .halfGoal:
            return "\(done) 했어요. 목표 \(goalText)의 절반이에요."
        case .fullGoal:
            return "\(done)로 목표 \(goalText)을 채웠어요."
        case .started, .resumed:
            return done
        case .finished:
            return "오늘 \(done) 했어요."
        }
    }

    /// 친구의 이 이벤트를 나에게 띄울 문구. 서버에서 이벤트를 받으면 이걸 쓴다.
    func friendBody(name: String) -> String {
        let done = TimeFormat.human(seconds)
        switch kind {
        case .started:  return "\(name) 님이 공부를 시작했어요."
        case .resumed:  return "\(name) 님이 다시 책상에 앉았어요."
        case .halfGoal: return "\(name) 님이 목표의 절반을 넘겼어요. (\(done))"
        case .fullGoal: return "\(name) 님이 목표를 채웠어요. (\(done))"
        case .finished: return "\(name) 님이 오늘 \(done) 하고 마쳤어요."
        }
    }

    private var goalText: String {
        goalMinutes % 60 == 0
            ? "\(goalMinutes / 60)시간"
            : "\(goalMinutes / 60)시간 \(goalMinutes % 60)분"
    }
}
