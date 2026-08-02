import Foundation
import Combine

/// 앱의 단일 상태 저장소.
///
/// 모든 날은 `DayRecord` 하나로 동등하다. "지금 어느 날짜를 재고 있나"는
/// `measuringKey`가 들고 있고 **저장하지 않는다** — 앱을 다시 켜면 항상 오늘부터다.
///
/// 자정을 넘겨도 재는 동안에는 날짜가 바뀌지 않는다. 새벽까지 공부하면 그 시간이
/// 전부 시작한 날에 쌓이고, 자고 일어나 앱을 다시 켜면 오늘로 돌아온다.
@MainActor
final class StudyStore: ObservableObject {

    @Published private(set) var data: AppData

    /// 지금 시간을 쌓고 있는 날짜. 저장하지 않는다.
    @Published private(set) var measuringKey: String

    /// 측정 중인지. 저장하지 않는다 — 앱을 끄면 항상 멈춘 상태로 돌아온다.
    @Published private(set) var isRunning = false

    /// 이번 회차를 시작한 시각. 측정 중일 때만 값이 있다.
    ///
    /// **초 단위 갱신은 이 값 하나에서 계산한다.** 매초 `data`를 건드리면
    /// `@Published`가 화면 전체에 변경을 알려 트리가 통째로 다시 평가된다 —
    /// 숫자 한 칸 바꾸자고 배경·메모지·유리 표면까지 전부 다시 그리는 셈이다.
    /// 그래서 흐르는 시간은 여기 두고, 기록에는 멈추는 순간에만 접어 넣는다.
    private var runStartedAt: Date?

    private var ticker: AnyCancellable?

    /// 공부하다 벌어진 일을 흘려보내는 창구.
    ///
    /// `@Published`가 아니라 `PassthroughSubject`인 게 중요하다 — 이벤트를 보낸다고
    /// 화면 전체가 다시 평가되면 안 된다. 구독하는 쪽만 받는다.
    let events = PassthroughSubject<StudyEvent, Never>()

    /// 목표 돌파를 한 번만 알리기 위해 직전 진행률을 들고 있다.
    /// 저장하지 않는다 — 앱을 다시 켜면 지금 값에서 다시 시작하므로,
    /// 이미 넘긴 지점을 다시 알리지 않는다.
    private var lastProgress: Double = 0

    private let fileURL: URL

    // MARK: 저장 스케줄

    /// 인코딩과 디스크 쓰기는 여기서 한다. 직렬 큐라 순서가 뒤집히지 않는다.
    private let ioQueue = DispatchQueue(label: "com.yeekrim.cagong.save", qos: .utility)
    private var pendingWrite: DispatchWorkItem?
    private var lastWrite = Date.distantPast

    /// 측정 중 tick을 디스크에 반영하는 간격. 사용자 행동에는 적용되지 않는다.
    private static let tickWriteInterval: TimeInterval = 5

    // MARK: - 수명

    /// - Parameter fileURL: 저장 위치. nil이면 Application Support/Cagong에 쓴다.
    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let dir = support.appendingPathComponent("Cagong", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("study-data.json")
        }

        data = Self.load(from: self.fileURL) ?? AppData()
        measuringKey = DateKey.today()
    }

    /// 스냅샷 렌더링용으로 상태를 통째로 갈아끼운다. 앱 흐름에서는 쓰지 않는다.
    func loadFixture(_ fixture: AppData, measuring key: String? = nil) {
        data = fixture
        measuringKey = key ?? DateKey.today()
    }

    // MARK: - 파생 상태

    var settings: AppSettings { data.settings }
    var theme: Theme { Theme.by(settings.themeID) }
    var drink: Drink { Drink.by(settings.drinkID) }

    /// 재고 있는 날의 기록
    var measuringDay: DayRecord? { data.days[measuringKey] }

    /// 재고 있는 날이 오늘이 아닌지. 화면에 눈에 띄게 알려야 한다.
    var isMeasuringPastDay: Bool { measuringKey != DateKey.today() }

    /// 측정 화면을 보여줄지(= 그날이 열려 있는지).
    /// 기록이 없거나 마무리했으면 시작 화면으로 간다.
    var isDayOpen: Bool {
        guard let day = data.days[measuringKey] else { return false }
        return !day.closed
    }

    /// 재고 있는 날의 할 일
    var todos: [TodoItem] { data.days[measuringKey]?.todos ?? [] }

    /// 할 일 글자를 고칠 수 있는 날인지. 지난 날의 내용은 잠근다.
    var canEditTodoText: Bool { measuringKey == DateKey.today() }

    // MARK: - 날짜 고르기

    /// 잴 수 있는 날짜는 오늘과 어제뿐이다.
    func canMeasure(_ key: String) -> Bool {
        key == DateKey.today() || key == DateKey.yesterday()
    }

    /// 잴 날짜를 바꾼다. 고른 날에 기록이 없으면 만들고, 마무리돼 있었으면 다시 연다.
    func setMeasuringDate(_ key: String) {
        guard canMeasure(key), key != measuringKey else { return }
        pause()

        var day = data.days[key] ?? DayRecord()
        day.closed = false
        data.days[key] = day

        measuringKey = key
        save()
    }

    // MARK: - 하루 시작 / 마무리

    /// 시작 화면에서 적은 할 일을 안고 그날을 연다.
    /// 이미 기록이 있으면 지우지 않고 이어붙인다.
    func beginDay(todos drafts: [TodoItem]) {
        var day = data.days[measuringKey] ?? DayRecord()
        day.todos.append(contentsOf: drafts)
        day.closed = false
        data.days[measuringKey] = day
        save()
    }

    /// 하루를 마무리한다.
    ///
    /// **잠그지 않는다.** 기록은 그대로 남고 언제든 다시 시작할 수 있다.
    /// 안 눌러도 아무 문제가 없다 — 날짜가 바뀌면 새 날이 알아서 생긴다.
    func endDay() {
        pause()
        data.days[measuringKey]?.closed = true
        data.days[measuringKey]?.endedAt = Date()

        emit(.finished, at: Date(), on: measuringKey)

        // 마무리했으면 다시 오늘로 돌아온다.
        measuringKey = DateKey.today()
        flush()
    }

    // MARK: - 측정
    //
    // 흐르는 시간은 `runStartedAt` 하나로 표현한다. 기록(`data`)은 멈추거나
    // 저장할 때만 건드린다 — 매초 건드리면 화면 전체가 다시 평가되기 때문이다.
    // 화면의 숫자는 `TimelineView`가 스스로 굴리며 `seconds(for:at:)`를 읽어간다.

    func start() {
        guard !isRunning else { return }

        // 아직 기록이 없는 날이면 만들어 주고, 마무리돼 있었으면 다시 연다.
        // 이미 열려 있으면 손대지 않는다 — 같은 값을 다시 넣어도 `@Published`는
        // 변경을 알리고, 그러면 화면 전체가 공짜로 한 번 더 평가된다.
        if data.days[measuringKey] == nil {
            data.days[measuringKey] = DayRecord()
        } else if data.days[measuringKey]?.closed == true {
            data.days[measuringKey]?.closed = false
        }

        let now = Date()
        // 앉기 **전**에 세어야 처음인지 다시인지를 가른다.
        let firstSitToday = (data.days[measuringKey]?.sessions.isEmpty ?? true)

        runStartedAt = now
        // 언제 앉았는지를 남긴다. 총합과 별개로 "몇 시에 시작했나"가 통계가 된다.
        data.days[measuringKey]?.sessions.append(StudySession(start: now))
        isRunning = true

        // 이미 넘긴 목표 지점을 다시 알리지 않도록 기준선을 지금 값으로 잡는다.
        lastProgress = goalProgress(for: measuringKey, at: now)
        emit(firstSitToday ? .started : .resumed, at: now)

        // 이 타이머는 화면과 무관하다. 주기적으로 파일에 옮겨 적기만 한다.
        ticker = Timer.publish(every: Self.tickWriteInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.checkGoalMilestones()
                    self?.scheduleWrite()
                }
            }
    }

    /// 멈추는 순간은 "여기까지는 확실히 남아야 하는" 지점이라 바로 쓴다.
    /// 노트북을 덮거나 앱을 강제 종료해도 이 시점까지는 지켜진다.
    func pause() {
        guard isRunning else { return }
        let now = Date()
        checkGoalMilestones(at: now)
        commit(at: now)
        closeOpenSession(at: now)
        isRunning = false
        runStartedAt = nil
        ticker?.cancel()
        ticker = nil
        flush()
    }

    func toggleRunning() { isRunning ? pause() : start() }

    /// 아직 접어넣지 않은 시간을 기록에 반영한다. **`data`가 바뀌는 유일한 지점이다.**
    ///
    /// 시작 시각과의 차이로 계산하므로 앱이 잠들었다 깨어나도 시간이 새지 않는다.
    /// 자정을 넘겨도 `measuringKey`는 그대로다 — 새벽 공부는 시작한 날에 쌓인다.
    private func commit(at now: Date = Date()) {
        guard isRunning, let started = runStartedAt else { return }
        let delta = max(0, now.timeIntervalSince(started))
        runStartedAt = now

        guard data.days[measuringKey] != nil else { return }
        data.days[measuringKey]?.seconds += delta
    }

    // MARK: - 이벤트

    /// 목표의 절반·전부를 **넘어서는 순간**에 한 번씩 알린다.
    ///
    /// 진행률은 줄어들지 않으므로 "직전 값보다 크고 임계값을 넘었다"로 판단하면
    /// 중복이 없다. 앱을 다시 켰을 때 이미 넘어 있으면 기준선이 그 값이라 조용하다.
    private func checkGoalMilestones(at now: Date = Date()) {
        guard isRunning else { return }
        let progress = goalProgress(for: measuringKey, at: now)
        defer { lastProgress = max(lastProgress, progress) }

        for (threshold, kind) in [(0.5, StudyEventKind.halfGoal), (1.0, .fullGoal)]
        where lastProgress < threshold && progress >= threshold {
            emit(kind, at: now)
        }
    }

    private func emit(_ kind: StudyEventKind, at now: Date, on key: String? = nil) {
        let target = key ?? measuringKey
        events.send(StudyEvent(
            kind: kind,
            at: now,
            dayKey: target,
            seconds: seconds(for: target, at: now),
            goalMinutes: goalMinutes(for: target)
        ))
    }

    /// 열려 있는 구간을 닫는다. 여러 개가 열려 있을 일은 없지만 방어적으로 전부 닫는다.
    private func closeOpenSession(at now: Date) {
        guard var day = data.days[measuringKey] else { return }
        guard day.sessions.contains(where: \.isOpen) else { return }

        for i in day.sessions.indices where day.sessions[i].isOpen {
            day.sessions[i].end = now
        }
        data.days[measuringKey] = day
    }

    // MARK: - 할 일

    /// 오늘 기록에만 새 항목을 넣을 수 있다.
    func addTodo(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canEditTodoText else { return }

        if data.days[measuringKey] == nil { data.days[measuringKey] = DayRecord() }
        data.days[measuringKey]?.todos.append(TodoItem(text: trimmed))
        save()
    }

    /// 체크는 **어느 날이든 언제든** 바꿀 수 있다.
    /// 어제 항목을 오늘 끝냈다면 그걸 표시할 수 있어야 한다.
    func toggleTodo(_ id: UUID, on key: String? = nil) {
        let target = key ?? measuringKey
        guard let idx = data.days[target]?.todos.firstIndex(where: { $0.id == id }) else { return }
        data.days[target]?.todos[idx].done.toggle()
        save()
    }

    /// 글자를 고칠 수 있는 날에서만 지울 수 있다.
    func removeTodo(_ id: UUID) {
        guard canEditTodoText else { return }
        data.days[measuringKey]?.todos.removeAll { $0.id == id }
        save()
    }

    // MARK: - 루틴 (고정한 할 일)

    /// 고정을 켜고 끈다.
    ///
    /// 켜면 다음 날부터 자동으로 따라오고, 끄면 **그날의 평범한 할 일로 남는다.**
    /// 끈다고 지워지지 않는 게 중요하다 — 오늘 이미 한 일이 사라지면 안 된다.
    func togglePin(_ id: UUID, on key: String? = nil) {
        let target = key ?? measuringKey
        guard let idx = data.days[target]?.todos.firstIndex(where: { $0.id == id }) else { return }
        data.days[target]?.todos[idx].pinned.toggle()
        save()
    }

    /// 새 날에 자동으로 따라올 항목들.
    ///
    /// **가장 최근에 기록이 있는 날**에서 가져온다. 며칠 쉬어도 루틴은 살아 있다.
    /// 이미 그날에 올려둔 항목이 있으면 중복해서 넣지 않는다.
    func routineDrafts(for key: String) -> [TodoItem] {
        let existing = Set(todos(for: key).map(\.text))

        guard let source = data.days.keys
            .filter({ $0 < key && !(data.days[$0]?.todos.isEmpty ?? true) })
            .max()
        else { return [] }

        return (data.days[source]?.todos ?? [])
            .filter { $0.pinned && !existing.contains($0.text) }
            .map(\.carriedToNewDay)
    }

    // MARK: - 하루 목표

    /// 그날의 목표(분). 따로 정하지 않았으면 마지막으로 쓴 기본값을 따른다.
    func goalMinutes(for key: String) -> Int {
        data.days[key]?.goalMinutes ?? settings.dailyGoalMinutes
    }

    func goalSeconds(for key: String) -> TimeInterval {
        TimeInterval(goalMinutes(for: key) * 60)
    }

    /// 목표 대비 진행률 0…1 (넘겨도 1로 자름)
    func goalProgress(for key: String, at now: Date = Date()) -> Double {
        let goal = goalSeconds(for: key)
        guard goal > 0 else { return 0 }
        return min(1, seconds(for: key, at: now) / goal)
    }

    /// 그날의 목표를 정한다.
    ///
    /// 기본값도 같이 옮겨둔다 — 목표를 바꿨다는 건 요즘 그만큼 하고 있다는 뜻이라,
    /// 내일도 그 값에서 시작하는 편이 맞다.
    func setGoal(minutes: Int, for key: String? = nil) {
        let target = key ?? measuringKey
        let clamped = max(30, min(12 * 60, minutes))

        if data.days[target] == nil { data.days[target] = DayRecord() }
        data.days[target]?.goalMinutes = clamped
        data.settings.dailyGoalMinutes = clamped
        save()
    }

    // MARK: - 설정

    func setTheme(_ id: ThemeID) {
        data.settings.themeID = id
        save()
    }

    func setDrink(_ id: DrinkID) {
        data.settings.drinkID = id
        save()
    }

    func setPhotoScene(_ id: String?) {
        data.settings.photoSceneID = id
        save()
    }

    /// 사진 장면을 앞뒤로 넘긴다.
    func stepPhotoScene(_ offset: Int) {
        guard let next = PhotoLibrary.shared.neighbour(of: data.settings.photoSceneID, offset: offset)
        else { return }
        setPhotoScene(next.id)
    }

    // MARK: - 나 · 친구

    var profile: Profile { data.profile }
    var friends: [Friend] { data.friends }
    var friendIDs: [UUID] { data.friends.map(\.id) }

    func setMyName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != data.profile.name else { return }
        data.profile.name = trimmed
        save()
    }

    /// 친구를 등록한다. 이미 있으면(같은 id) 이름만 갱신한다. 나 자신은 못 넣는다.
    func addFriend(_ friend: Friend) {
        guard friend.id != data.profile.id else { return }
        if let idx = data.friends.firstIndex(where: { $0.id == friend.id }) {
            data.friends[idx] = friend
        } else {
            data.friends.append(friend)
        }
        save()
    }

    func removeFriend(_ id: UUID) {
        data.friends.removeAll { $0.id == id }
        save()
    }

    /// 서버가 준 수락된 친구 목록으로 로컬 캐시를 통째로 맞춘다.
    /// 바뀐 게 없으면 아무것도 안 한다 — 8초마다 공짜 저장·리렌더를 하지 않으려고.
    func syncFriends(_ list: [Friend]) {
        let sorted = list.sorted { $0.id.uuidString < $1.id.uuidString }
        let current = data.friends.sorted { $0.id.uuidString < $1.id.uuidString }
        guard sorted != current else { return }
        data.friends = list
        save()
    }

    func friend(_ id: UUID) -> Friend? { data.friends.first { $0.id == id } }

    // MARK: - 조회

    func record(for key: String) -> DayRecord? { data.days[key] }

    /// 그날의 지금 이 순간 기록.
    ///
    /// 측정 중이면 아직 기록에 접어넣지 않은 시간까지 더해서 돌려준다.
    /// **읽기만 하므로 아무것도 다시 그려지지 않는다** — 화면은 `TimelineView`가
    /// 자기 리듬으로 이 값을 다시 읽어가는 방식으로 굴러간다.
    func seconds(for key: String, at now: Date = Date()) -> TimeInterval {
        let committed = data.days[key]?.seconds ?? 0
        guard isRunning, key == measuringKey, let started = runStartedAt else { return committed }
        return committed + max(0, now.timeIntervalSince(started))
    }

    /// 재고 있는 날의 지금 시간
    func displaySeconds(at now: Date = Date()) -> TimeInterval {
        seconds(for: measuringKey, at: now)
    }

    func todos(for key: String) -> [TodoItem] { data.days[key]?.todos ?? [] }

    func sessions(for key: String) -> [StudySession] { data.days[key]?.sessions ?? [] }

    /// 그날 처음 앉은 시각
    func firstStart(for key: String) -> Date? { data.days[key]?.firstStart }

    /// 그날 마지막으로 손 뗀 시각. Zzz를 눌렀으면 그 시각.
    func lastEnd(for key: String) -> Date? { data.days[key]?.lastEnd }

    /// 지금 재고 있는 날인지
    func isMeasuring(_ key: String) -> Bool { key == measuringKey && isRunning }

    func hasAnything(_ key: String) -> Bool {
        seconds(for: key) > 0 || !todos(for: key).isEmpty
    }

    /// 해당 월의 총 공부시간
    func monthTotal(year: Int, month: Int, at now: Date = Date()) -> TimeInterval {
        let prefix = String(format: "%04d-%02d", year, month)
        return data.days.keys
            .filter { $0.hasPrefix(prefix) }
            .reduce(0) { $0 + seconds(for: $1, at: now) }
    }

    /// 해당 월에 공부한 날 수
    func monthStudiedDays(year: Int, month: Int) -> Int {
        let prefix = String(format: "%04d-%02d", year, month)
        return data.days.filter { $0.key.hasPrefix(prefix) && $0.value.seconds > 0 }.count
    }

    // MARK: - 영속화
    //
    // 저장은 메인 스레드를 붙잡지 않는다. **다만 미루지도 않는다.**
    //
    // 화살표·테마·체크는 누를 때마다 상태가 바뀌는데, 그때마다 파일 전체를
    // 인코딩해 디스크에 쓰면 클릭 한 번이 10ms 안팎을 잡아먹는다 — 기록이 3년치
    // 쌓이면 27ms로, 한 프레임(16.6ms)을 넘긴다. 눌러도 반응이 없는 것처럼 느껴진다.
    //
    // 그 비용은 **디스크를 기다린 것**이지 자주 쓴 게 아니다. 그래서 고칠 것은
    // 기다리지 않는 것 하나뿐이다. 메인 스레드는 값 타입을 복사해 넘기기만 하고
    // (0.04ms), 인코딩과 쓰기는 백그라운드 큐가 맡는다.
    //
    // 사용자가 한 행동을 몇 초씩 묶어두면 그만큼이 유실 구간이 된다.
    // 빨라지지도 않으면서 잃을 것만 생기므로 그렇게 하지 않는다.

    /// 사용자가 한 행동. 미루지 않고 바로 넘긴다.
    private func save() {
        scheduleWrite()
    }

    /// 같은 런루프 턴에 몰린 변경은 하나로 합쳐진다.
    /// 연타해도 마지막 상태 한 번만 쓰이고, 순서가 뒤집히지 않는다.
    private func scheduleWrite() {
        pendingWrite?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.handOffWrite() }
        }
        pendingWrite = item
        DispatchQueue.main.async(execute: item)
    }

    /// 파일에 쓸 값.
    ///
    /// 측정 중이라 아직 접어넣지 않은 시간이 있으면 **복사본에만** 얹는다.
    /// `data`를 건드리지 않으므로 주기적인 저장이 화면을 다시 그리지 않는다.
    private func snapshotForWrite(at now: Date = Date()) -> AppData {
        var copy = data
        guard isRunning, var day = copy.days[measuringKey] else { return copy }

        day.seconds = seconds(for: measuringKey, at: now)

        // 열린 구간은 지금 시각으로 닫아서 내보낸다.
        // 파일에 `end: nil`이 남지 않으므로 앱이 갑자기 꺼져도 다음에 열 때 고칠 게 없다.
        for i in day.sessions.indices where day.sessions[i].isOpen {
            day.sessions[i].end = now
        }

        copy.days[measuringKey] = day
        return copy
    }

    /// 메인 스레드에서는 값만 복사하고(구조체라 싸다) 인코딩·쓰기는 큐로 넘긴다.
    private func handOffWrite() {
        pendingWrite = nil
        lastWrite = Date()

        let snapshot = snapshotForWrite()
        let url = fileURL
        ioQueue.async { Self.write(snapshot, to: url) }
    }

    /// 지금 당장, 확실히 쓴다.
    ///
    /// 앱 종료 직전과 측정을 멈출 때처럼 **여기서 잃으면 안 되는** 지점에서만 부른다.
    /// 예약된 쓰기가 있으면 취소하고, 큐를 통해 동기로 써서 먼저 넘긴 옛 내용이
    /// 새 내용을 덮어쓰는 일이 없게 한다.
    func flush() {
        pendingWrite?.cancel()
        pendingWrite = nil
        lastWrite = Date()

        let snapshot = snapshotForWrite()
        let url = fileURL
        ioQueue.sync { Self.write(snapshot, to: url) }
    }

    /// 사람이 읽기 좋은 들여쓰기는 넣지 않는다 — 파일이 세 배로 커지고
    /// 인코딩도 그만큼 느려진다. 키 정렬만 유지해 매번 같은 바이트가 나오게 한다.
    nonisolated private static func write(_ data: AppData, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(data) else { return }
        try? encoded.write(to: url, options: .atomic)
    }

    private static func load(from url: URL) -> AppData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppData.self, from: raw)
    }
}
