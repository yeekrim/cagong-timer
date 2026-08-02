import Foundation
import Combine

/// 날짜 선택 모델의 동작을 검증한다.
///
///   swiftc -parse-as-library -target arm64-apple-macos14.0 -o storetest \
///       $(find Sources/Cagong -name '*.swift' ! -name 'CagongApp.swift') Tools/StoreTest.swift
@main
@MainActor
struct StoreTest {

    static var failures = 0

    static func check(_ label: String, _ condition: Bool) {
        print("\(condition ? "✓" : "✗") \(label)")
        if !condition { failures += 1 }
    }

    static func tempFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cagong-test-\(UUID().uuidString).json")
    }

    /// 저장은 메인 큐에 예약됐다가 백그라운드에서 일어난다.
    /// `Thread.sleep`은 큐를 돌리지 않으므로 런루프를 실제로 굴려야 한다.
    static func settle(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: deadline)
        }
    }

    /// 파일에 실제로 쓰인 내용만 읽는다. 메모리 상태는 보지 않는다.
    static func onDisk(_ url: URL) -> AppData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(AppData.self, from: raw)
    }

    static func main() {
        let today = DateKey.today()
        let yesterday = DateKey.yesterday()

        // ── 기본: 앱을 켜면 오늘부터 ─────────────────────────────
        print("── 앱을 켜면 오늘이 이미 골라져 있다 ──")
        let file = tempFile()
        let s1 = StudyStore(fileURL: file)

        check("재는 날짜가 오늘이다", s1.measuringKey == today)
        check("지난 날을 재고 있지 않다", !s1.isMeasuringPastDay)
        check("아직 연 날이 없어 시작 화면이다", !s1.isDayOpen)
        check("오늘 할 일 글자를 고칠 수 있다", s1.canEditTodoText)

        // ── 하루 시작 → 측정 ────────────────────────────────────
        print("\n── 시작 화면에서 할 일을 안고 시작 ──")
        s1.beginDay(todos: [TodoItem(text: "가"), TodoItem(text: "나")])
        check("측정 화면으로 넘어간다", s1.isDayOpen)
        check("할 일 2개", s1.todos.count == 2)

        // Thread.sleep은 런루프를 세워버려 타이머가 아예 안 뜬다.
        // 실제 앱처럼 굴러가게 하려면 런루프를 돌려야 한다.
        //
        // 측정 중에는 store가 화면에 변경을 알리지 **않아야** 한다.
        // 알리면 배경·메모지·유리 표면까지 트리 전체가 다시 평가된다 —
        // 숫자 한 칸 바꾸자고. 화면은 TimelineView가 스스로 굴린다.
        s1.start()

        // 시작 자체는 알려야 한다(버튼 글자가 바뀐다). 재는 건 그 다음부터다.
        var notices = 0
        let watch = s1.objectWillChange.sink { _ in notices += 1 }
        settle(2.1)
        check("측정 중 시간이 흐른다 (\(String(format: "%.1f", s1.displaySeconds()))초)",
              s1.displaySeconds() >= 2.0)
        check("흐르는 동안 화면 전체에 변경을 알리지 않는다 (\(notices)회)", notices == 0)
        watch.cancel()

        // 매초 파일 전체를 다시 쓰지도 않는다.
        check("측정 중에는 디스크가 따라오지 않는다",
              (onDisk(file)?.days[today]?.seconds ?? 0) < 1.0)

        s1.pause()
        let measured = s1.displaySeconds()
        check("2초 이상 측정됨 (\(String(format: "%.1f", measured))초)", measured >= 2.0)
        check("오늘 기록에 쌓였다", abs(s1.seconds(for: today) - measured) < 0.05)
        check("멈추는 순간 디스크가 정확히 맞춰진다",
              abs((onDisk(file)?.days[today]?.seconds ?? 0) - measured) < 0.05)

        s1.toggleTodo(s1.todos[0].id)
        check("첫 항목이 체크됐다", s1.todos[0].done)

        // ── 저장은 붙잡지도, 미루지도 않는다 ───────────────────────
        //
        // 사용자가 한 행동은 디스크를 기다리지 않고 넘어가되, 곧바로 쓰인다.
        // 몇 초씩 묶어두면 딱 그만큼이 유실 구간이 되므로 미루지 않는다.
        print("\n── 저장이 클릭을 붙잡지도, 미루지도 않는다 ──")

        settle(0.05)
        check("체크는 곧바로 파일에 반영된다",
              onDisk(file)?.days[today]?.todos.first?.done == true)

        // 연타는 한 번의 쓰기로 합쳐지되, 마지막 상태가 남는다.
        for _ in 0..<10 { s1.toggleTodo(s1.todos[0].id) }
        settle(0.05)
        check("연타해도 마지막 상태가 남는다",
              onDisk(file)?.days[today]?.todos.first?.done == s1.todos[0].done)

        // 테마·음료 같은 설정도 마찬가지다.
        s1.setDrink(.matchaLatte)
        settle(0.05)
        check("설정도 곧바로 쓰인다", onDisk(file)?.settings.drinkID == .matchaLatte)

        // flush는 런루프조차 기다리지 않고 그 자리에서 쓴다.
        s1.toggleTodo(s1.todos[0].id)
        s1.flush()
        check("flush는 기다리지 않고 즉시 쓴다",
              onDisk(file)?.days[today]?.todos.first?.done == s1.todos[0].done)

        // 뒤이어 나올 검사들이 기대하는 상태로 되돌린다.
        if s1.todos[0].done == false { s1.toggleTodo(s1.todos[0].id) }
        s1.flush()

        // ── 앱을 껐다 켠다 ──────────────────────────────────────
        print("\n── 앱을 껐다 켠다 ──")
        let s2 = StudyStore(fileURL: file)
        check("측정 시간이 복구됐다", abs(s2.seconds(for: today) - measured) < 0.05)
        check("체크 상태가 복구됐다", s2.todos.first?.done == true)
        check("멈춘 상태로 시작한다", !s2.isRunning)
        check("날짜는 다시 오늘", s2.measuringKey == today)

        // ── 어제로 바꿔서 재기 ──────────────────────────────────
        print("\n── 어제를 골라서 잰다 (새벽 공부 케이스) ──")
        check("어제는 잴 수 있다", s2.canMeasure(yesterday))
        check("그제는 못 잰다", !s2.canMeasure(twoDaysAgo()))

        s2.setMeasuringDate(yesterday)
        check("재는 날짜가 어제로 바뀌었다", s2.measuringKey == yesterday)
        check("지난 날을 재고 있다고 알려준다", s2.isMeasuringPastDay)
        check("어제는 할 일 글자를 못 고친다", !s2.canEditTodoText)

        s2.start()
        Thread.sleep(forTimeInterval: 1.1)
        s2.pause()
        let yTime = s2.seconds(for: yesterday)
        check("어제 기록에 쌓였다 (\(TimeFormat.human(yTime)))", yTime >= 1.0)
        check("오늘 기록은 그대로다", abs(s2.seconds(for: today) - measured) < 0.05)

        print("\n── 어제에는 할 일을 새로 못 넣는다 ──")
        let beforeAdd = s2.todos.count
        s2.addTodo("어제에 끼워넣기")
        check("추가가 막힌다", s2.todos.count == beforeAdd)

        // ── 앱 재시작 시 오늘로 리셋 ─────────────────────────────
        print("\n── 어제를 재던 중 앱을 다시 켠다 ──")
        let s3 = StudyStore(fileURL: file)
        check("무조건 오늘로 리셋된다", s3.measuringKey == today)
        check("어제 기록은 남아 있다", abs(s3.seconds(for: yesterday) - yTime) < 0.05)

        // ── 체크는 어느 날이든 언제든 ────────────────────────────
        print("\n── 지난 날 체크박스는 언제든 수정 가능 ──")
        var past = DayRecord(seconds: 3600, todos: [TodoItem(text: "옛 항목")], closed: true)
        past.endedAt = Date()
        let pastKey = "2020-01-15"
        var fixture = s3.data
        fixture.days[pastKey] = past
        s3.loadFixture(fixture)

        check("그날 할 일이 보인다", s3.todos(for: pastKey).count == 1)
        let pastID = s3.todos(for: pastKey)[0].id
        s3.toggleTodo(pastID, on: pastKey)
        check("5년 전 항목도 체크된다", s3.todos(for: pastKey)[0].done)

        // ── 마무리는 잠그지 않는다 ───────────────────────────────
        print("\n── 마무리(Zzz)는 잠그지 않는다 ──")
        let s4 = StudyStore(fileURL: tempFile())
        s4.beginDay(todos: [TodoItem(text: "하나")])
        s4.start(); Thread.sleep(forTimeInterval: 1.1); s4.pause()
        let before = s4.seconds(for: today)

        s4.endDay()
        check("시작 화면으로 돌아간다", !s4.isDayOpen)
        check("기록은 지워지지 않는다", abs(s4.seconds(for: today) - before) < 0.05)
        check("할 일도 남아 있다", s4.todos(for: today).count == 1)

        s4.start()
        check("다시 시작할 수 있다", s4.isRunning)
        check("다시 측정 화면이다", s4.isDayOpen)
        Thread.sleep(forTimeInterval: 1.1)
        s4.pause()
        check("이어서 쌓인다", s4.seconds(for: today) > before)

        // ── 옛 형식 이관 ────────────────────────────────────────
        print("\n── 옛 저장 파일을 읽는다 (active → days) ──")
        let legacyFile = tempFile()
        let legacyJSON = """
        {
          "version": 1,
          "settings": { "themeID": "cafe", "dailyGoalMinutes": 240, "drinkID": "americano" },
          "active": {
            "dateKey": "\(yesterday)",
            "startedAt": "2026-07-30T12:00:00Z",
            "accumulated": 7200,
            "todos": [{ "id": "\(UUID().uuidString)", "text": "옛 진행중", "done": false }]
          },
          "days": {
            "2026-07-01": { "seconds": 3600, "todos": [], "endedAt": "2026-07-01T12:00:00Z" }
          }
        }
        """
        try? legacyJSON.write(to: legacyFile, atomically: true, encoding: .utf8)
        let s5 = StudyStore(fileURL: legacyFile)

        check("마감된 옛 기록이 살아 있다", abs(s5.seconds(for: "2026-07-01") - 3600) < 0.05)
        check("진행 중이던 하루가 그날 기록으로 접혔다", abs(s5.seconds(for: yesterday) - 7200) < 0.05)
        check("그 할 일도 딸려왔다", s5.todos(for: yesterday).count == 1)
        check("옛 마감 기록은 닫힌 상태", s5.record(for: "2026-07-01")?.closed == true)
        check("진행 중이던 날은 열린 상태", s5.record(for: yesterday)?.closed == false)

        // ── 하루 목표는 날마다 다르다 ─────────────────────────────
        print("\n── 목표를 날짜별로 정한다 ──")
        let g = StudyStore(fileURL: tempFile())
        g.beginDay(todos: [])

        let defaultGoal = g.settings.dailyGoalMinutes
        check("안 정했으면 기본 목표를 따른다 (\(defaultGoal)분)",
              g.goalMinutes(for: today) == defaultGoal)

        g.setGoal(minutes: 360)
        check("오늘 목표가 6시간이 됐다", g.goalMinutes(for: today) == 360)
        check("기본값도 따라 옮겨진다", g.settings.dailyGoalMinutes == 360)

        g.setGoal(minutes: 120, for: yesterday)
        check("어제는 따로 2시간", g.goalMinutes(for: yesterday) == 120)
        check("오늘은 6시간 그대로", g.goalMinutes(for: today) == 360)

        g.setGoal(minutes: 5)
        check("30분 밑으로는 안 내려간다", g.goalMinutes(for: today) == 30)
        g.setGoal(minutes: 9999)
        check("12시간 위로는 안 올라간다", g.goalMinutes(for: today) == 720)

        g.setGoal(minutes: 120)
        var day = g.record(for: today) ?? DayRecord()
        day.seconds = 3600
        var gFixture = g.data
        gFixture.days[today] = day
        g.loadFixture(gFixture)
        check("진행률은 그날 목표 기준 (1시간 / 2시간 = 50%)",
              abs(g.goalProgress(for: today) - 0.5) < 0.001)

        // ── 루틴 (고정한 할 일) ───────────────────────────────────
        print("\n── 고정한 할 일이 다음 날 따라온다 ──")
        let r = StudyStore(fileURL: tempFile())
        r.beginDay(todos: [
            TodoItem(text: "영단어 50개"),
            TodoItem(text: "오늘만 하는 일")
        ])

        check("처음엔 고정된 게 없다", r.routineDrafts(for: today).isEmpty)

        r.togglePin(r.todos[0].id)
        r.toggleTodo(r.todos[0].id)      // 오늘은 이미 끝냈다
        check("첫 항목이 고정됐다", r.todos[0].pinned)

        // 오늘을 지난 날로 밀어놓고 "다음 날"을 흉내낸다.
        let tomorrow = "2099-01-01"
        var rFixture = r.data
        rFixture.days[tomorrow] = DayRecord()
        r.loadFixture(rFixture, measuring: tomorrow)

        let carried = r.routineDrafts(for: tomorrow)
        check("고정한 것만 따라온다 (\(carried.count)개)", carried.count == 1)
        check("따라온 건 영단어", carried.first?.text == "영단어 50개")
        check("체크는 풀린 채로 온다", carried.first?.done == false)
        check("따라온 것도 고정 상태를 유지한다", carried.first?.pinned == true)
        check("새 항목이라 정체성이 다르다", carried.first?.id != r.todos(for: today)[0].id)

        r.beginDay(todos: carried)
        check("중복으로 또 넣지 않는다", r.routineDrafts(for: tomorrow).isEmpty)

        // 고정을 풀면 그날 항목으로 남되, 다음 날부터 안 따라온다.
        r.togglePin(r.todos[0].id)
        check("고정을 풀어도 그날에는 남는다", r.todos.count == 1)
        check("고정이 풀렸다", !r.todos[0].pinned)

        var rNext = r.data
        rNext.days["2099-01-02"] = DayRecord()
        r.loadFixture(rNext, measuring: "2099-01-02")
        check("다음 날엔 안 따라온다", r.routineDrafts(for: "2099-01-02").isEmpty)

        // ── 공부 구간 기록 ────────────────────────────────────────
        print("\n── 언제 앉아 언제 접었는지 남는다 ──")
        let sFile = tempFile()
        let ss = StudyStore(fileURL: sFile)
        ss.beginDay(todos: [])
        check("시작 전에는 구간이 없다", ss.sessions(for: today).isEmpty)
        check("시작 시각도 없다", ss.firstStart(for: today) == nil)

        let t0 = Date()
        ss.start()
        check("시작하면 구간이 하나 열린다", ss.sessions(for: today).count == 1)
        check("열린 구간은 끝이 비어 있다", ss.sessions(for: today)[0].isOpen)
        check("시작 시각이 기록됐다",
              abs((ss.firstStart(for: today) ?? .distantPast).timeIntervalSince(t0)) < 0.5)

        // 재는 도중 파일에는 열린 구간이 남지 않아야 한다.
        // 앱이 갑자기 꺼져도 다음에 열 때 고칠 게 없어야 하니까.
        settle(0.05)
        let openOnDisk = onDisk(sFile)?.days[today]?.sessions.contains { $0.isOpen } ?? true
        check("파일에는 열린 구간이 남지 않는다", !openOnDisk)

        settle(1.1)
        ss.pause()
        check("멈추면 구간이 닫힌다", ss.sessions(for: today)[0].end != nil)
        check("구간 길이가 총합과 맞는다",
              abs(ss.sessions(for: today)[0].length() - ss.seconds(for: today)) < 0.1)

        // 두 번째로 앉으면 구간이 하나 더 생긴다.
        ss.start(); settle(1.1); ss.pause()
        check("다시 앉으면 구간이 늘어난다", ss.sessions(for: today).count == 2)
        check("시작 시각은 처음 앉은 때 그대로",
              abs((ss.firstStart(for: today) ?? .distantPast).timeIntervalSince(t0)) < 0.5)
        check("총합은 두 구간의 합",
              abs(ss.seconds(for: today)
                  - ss.sessions(for: today).reduce(0) { $0 + $1.length() }) < 0.1)

        // Zzz를 누른 시각이 마무리 시각이 된다.
        ss.start(); settle(0.3)
        let beforeEnd = Date()
        ss.endDay()
        check("Zzz 시각이 마무리로 남는다",
              abs((ss.lastEnd(for: today) ?? .distantPast).timeIntervalSince(beforeEnd)) < 0.5)
        check("Zzz를 눌러도 구간은 그대로 남는다", ss.sessions(for: today).count == 3)

        // 껐다 켜도 구간이 살아 있다.
        let ss2 = StudyStore(fileURL: sFile)
        check("구간이 복구된다", ss2.sessions(for: today).count == 3)
        check("복구된 구간은 전부 닫혀 있다",
              !ss2.sessions(for: today).contains { $0.isOpen })

        // 옛 기록에는 구간이 없지만 총합은 살아 있다.
        var old = DayRecord(seconds: 7200, closed: true)
        old.endedAt = Date()
        var sFixture = ss2.data
        sFixture.days["2019-03-03"] = old
        ss2.loadFixture(sFixture)
        check("구간 없는 옛 기록도 총합은 그대로",
              abs(ss2.seconds(for: "2019-03-03") - 7200) < 0.05)
        check("구간이 없으면 시작 시각도 없다", ss2.firstStart(for: "2019-03-03") == nil)

        try? FileManager.default.removeItem(at: sFile)

        // ── 월 합계 ─────────────────────────────────────────────
        print("\n── 월 합계 ──")
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        let total = s4.monthTotal(year: c.year!, month: c.month!)
        check("이번 달 합계가 오늘 기록을 포함한다", total >= s4.seconds(for: today) - 0.05)

        for f in [file, legacyFile] { try? FileManager.default.removeItem(at: f) }

        print("\n" + (failures == 0 ? "전부 통과" : "\(failures)개 실패"))
        exit(failures == 0 ? 0 : 1)
    }

    static func twoDaysAgo() -> String {
        let d = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        return DateKey.string(from: d)
    }
}
