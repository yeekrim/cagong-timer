import SwiftUI

/// 월별 기록.
///
/// 날짜 칸마다 그날 총 공부시간이 들어가고, 칸은 컵처럼 아래에서 위로 채워진다.
/// 상단에 그 달의 총 공부시간이 있다.
struct MonthlyView: View {
    @EnvironmentObject private var store: StudyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let theme: Theme
    let namespace: Namespace.ID

    @State private var year: Int
    @State private var month: Int
    @State private var revealed = false
    /// 상세를 펼친 날짜. nil이면 닫힘.
    @State private var selectedKey: String?

    init(theme: Theme, namespace: Namespace.ID) {
        self.theme = theme
        self.namespace = namespace
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        _year = State(initialValue: now.year ?? 2026)
        _month = State(initialValue: now.month ?? 1)
    }

    var body: some View {
        // 측정 중에는 오늘 칸이 계속 자라야 한다. store는 이제 매초 알리지 않으므로
        // (그러면 화면 전체가 다시 평가된다) 여기서 분 단위로 직접 다시 읽는다.
        // 칸에 적히는 단위가 분이라 1분이면 충분하다.
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            board
        }
    }

    private var board: some View {
        VStack(spacing: 0) {
            header
            summary
                .padding(.top, 18)
            weekdayRow
                .padding(.top, 22)
            grid
                .padding(.top, 6)
        }
        // 폭을 고정하지 않는다. 날짜 칸은 이미 `maxWidth: .infinity`라
        // 창을 줄이면 격자가 알아서 좁아진다.
        .frame(maxWidth: 560)
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        // 작은 글자가 많은 면이라 틴트를 타이머 카드보다 조금 더 준다.
        .glass(
            RoundedRectangle(cornerRadius: 22, style: .continuous),
            tint: theme.p.card,
            tintOpacity: 0.24
        )
    }

    // MARK: 머리

    private var header: some View {
        HStack(spacing: 16) {
            DrinkGlass(
                running: store.isRunning,
                theme: theme,
                drink: store.drink,
                side: 46,
                compact: true
            )
            .matchedGeometryEffect(id: "cup", in: namespace)

            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: "Monthly", theme: theme, color: theme.p.accentSoft)
                Text("\(String(year))년 \(month)월")
                    .font(Typo.title(21))
                    .foregroundStyle(theme.p.ink)
            }

            Spacer()

            HStack(spacing: 4) {
                stepButton(systemName: "chevron.left", help: "이전 달") { step(-1) }
                stepButton(systemName: "chevron.right", help: "다음 달", disabled: isAtCurrentMonth) { step(1) }
            }
        }
    }

    private func stepButton(
        systemName: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(disabled ? theme.p.inkSoft.opacity(0.3) : theme.p.inkSoft)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(theme.p.ink.opacity(disabled ? 0 : 0.05))
                )
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled)
        .help(help)
    }

    // MARK: 요약

    private var summary: some View {
        HStack(spacing: 0) {
            stat(label: "Total", value: TimeFormat.human(monthTotal), emphasis: true)
            divider
            stat(label: "Days", value: "\(studiedDays)일")
            divider
            stat(label: "Average", value: averageText)
        }
        // 회색 박스로 감싸면 "큰 숫자 + 작은 라벨" 템플릿이 된다.
        // 위아래 헤어라인만 남겨 숫자가 종이 위에 바로 놓이게 한다.
        .padding(.vertical, 18)
        .overlay(alignment: .top) { hairline }
        .overlay(alignment: .bottom) { hairline }
    }

    private var hairline: some View {
        Rectangle()
            .fill(theme.p.cardStroke.opacity(0.8))
            .frame(height: 1)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.p.cardStroke.opacity(0.7))
            .frame(width: 1, height: 30)
    }

    /// 값의 글자 크기가 서로 달라서, 높이를 고정하지 않으면 라벨 줄이 어긋난다.
    private func stat(label: String, value: String, emphasis: Bool = false) -> some View {
        VStack(spacing: 8) {
            Eyebrow(text: label, theme: theme)
                .frame(height: 13, alignment: .bottom)

            Text(value)
                .font(emphasis ? Typo.title(22) : Typo.bodyStrong(15))
                .foregroundStyle(emphasis ? theme.p.ink : theme.p.inkSoft)
                .contentTransition(.numericText())
                .frame(height: 28, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.digit, value: value)
    }

    // MARK: 요일 / 격자

    private var weekdayRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(KoDate.weekdaySymbols.enumerated()), id: \.offset) { idx, sym in
                Text(sym)
                    .font(Typo.body(11.5))
                    .foregroundStyle(
                        idx == 0 ? theme.p.brass.opacity(0.9) : theme.p.inkSoft.opacity(0.75)
                    )
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 한 달은 최대 6주라 스크롤이 필요 없다. 고정 격자로 두고,
    /// 리빌은 주 단위로 시차를 둔 등장으로 처리한다.
    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                HStack(spacing: 6) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            let key = DateKey.string(from: day)
                            DayCell(
                                date: day,
                                seconds: store.seconds(for: key),
                                goalSeconds: store.goalSeconds(for: key),
                                inProgress: store.isMeasuring(key),
                                isToday: Calendar.current.isDateInToday(day),
                                selected: selectedKey == key,
                                theme: theme
                            )
                            .onTapGesture {
                                guard store.hasAnything(key) else { return }
                                selectedKey = (selectedKey == key) ? nil : key
                            }
                            .popover(
                                isPresented: Binding(
                                    get: { selectedKey == key },
                                    set: { if !$0, selectedKey == key { selectedKey = nil } }
                                ),
                                arrowEdge: .bottom
                            ) {
                                DayDetail(
                                    date: day,
                                    seconds: store.seconds(for: key),
                                    todos: store.todos(for: key),
                                    sessions: store.sessions(for: key),
                                    endedAt: store.record(for: key)?.closed == true
                                        ? store.record(for: key)?.endedAt : nil,
                                    inProgress: store.isMeasuring(key),
                                    theme: theme,
                                    onToggle: { store.toggleTodo($0, on: key) },
                                    onRemoveSession: { store.removeSession($0, on: key) }
                                )
                            }
                        } else {
                            Color.clear
                                .frame(height: 58)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 14)
                .animation(
                    reduceMotion ? nil : Motion.card.delay(Double(weekIndex) * 0.055),
                    value: revealed
                )
            }
        }
        .padding(.top, 8)
        .onAppear { revealed = true }
    }

    // MARK: 계산

    private var isAtCurrentMonth: Bool {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        return now.year == year && now.month == month
    }

    private var monthTotal: TimeInterval { store.monthTotal(year: year, month: month) }
    private var studiedDays: Int { store.monthStudiedDays(year: year, month: month) }

    private var averageText: String {
        guard studiedDays > 0 else { return "—" }
        return TimeFormat.human(monthTotal / Double(studiedDays))
    }

    /// 1일 앞의 빈 칸을 채우고 7개씩 끊는다.
    private var weeks: [[Date?]] { MonthGrid.weeks(year: year, month: month) }

    private func step(_ delta: Int) {
        withAnimation(Motion.screen) {
            var m = month + delta
            var y = year
            if m > 12 { m = 1; y += 1 }
            if m < 1 { m = 12; y -= 1 }
            month = m
            year = y
        }
    }
}

// MARK: - 달력 격자 계산

/// 월 달력의 주 배열을 만든다. 내 먼슬리와 친구 먼슬리가 같이 쓴다.
enum MonthGrid {
    /// 1일 앞의 빈 칸을 채우고 7개씩 끊는다. 빈 칸은 nil.
    static func weeks(year: Int, month: Int) -> [[Date?]] {
        let cal = Calendar.current
        guard
            let first = cal.date(from: DateComponents(year: year, month: month, day: 1)),
            let range = cal.range(of: .day, in: .month, for: first)
        else { return [] }

        let leading = cal.component(.weekday, from: first) - 1
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            cells.append(cal.date(from: DateComponents(year: year, month: month, day: d)))
        }
        while cells.count % 7 != 0 { cells.append(nil) }

        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }
}

// MARK: - 날짜 칸

/// 하루 한 칸. 그날 공부한 만큼 아래에서 채워진다.
/// 내 먼슬리와 친구 먼슬리가 같이 쓴다.
struct DayCell: View {
    let date: Date
    let seconds: TimeInterval
    let goalSeconds: TimeInterval
    let inProgress: Bool
    let isToday: Bool
    /// 상세가 펼쳐진 칸
    let selected: Bool
    let theme: Theme

    @State private var hovered = false

    private var fill: Double {
        guard goalSeconds > 0 else { return 0 }
        return min(1, seconds / goalSeconds)
    }

    private var day: Int { Calendar.current.component(.day, from: date) }
    private var hasRecord: Bool { seconds > 0 }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.p.ink.opacity(theme.isDark ? 0.12 : 0.045))

            // 채워지는 커피
            GeometryReader { g in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [theme.p.accentSoft.opacity(0.85), theme.p.accent],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: g.size.height * fill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .animation(Motion.card, value: fill)

            // 날짜는 위, 시간은 아래에 고정한다.
            // 위치가 고정돼야 각 글자가 커피에 덮이는지 판단할 수 있다.
            VStack(spacing: 0) {
                Text("\(day)")
                    .font(Typo.stamp(13))
                    .foregroundStyle(dayNumberColor)
                    .padding(.top, 7)

                Spacer(minLength: 0)

                if hasRecord {
                    Text(TimeFormat.compact(seconds))
                        .font(Typo.plain(10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(timeColor)
                        .contentTransition(.numericText())
                        .padding(.bottom, 7)
                }
            }
            .frame(maxHeight: .infinity)

            // 진행 중인 날 표시
            if inProgress {
                Circle()
                    .fill(theme.p.brass)
                    .frame(width: 5, height: 5)
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(height: 58)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(borderColor, lineWidth: selected ? 2 : (isToday ? 1.6 : 1))
        )
        .contentShape(Rectangle())
        .scaleEffect(selected ? 1.06 : (hovered ? 1.04 : 1))
        .animation(Motion.button, value: hovered)
        .animation(Motion.button, value: selected)
        .onHover { hovered = $0 }
        .help(hasRecord ? "\(KoDate.short(date)) · \(TimeFormat.human(seconds)) — 눌러서 그날 할 일 보기" : KoDate.short(date))
    }

    private var borderColor: Color {
        if selected { return theme.p.accent }
        if isToday { return theme.p.brass }
        return theme.p.cardStroke.opacity(hovered ? 0.9 : 0)
    }

    /// 커피 위에 얹힌 글자색.
    private var onCoffee: Color { theme.onAccent }

    /// 날짜 숫자는 칸 위쪽(아래에서 약 74% 높이)에 있다.
    /// 커피가 거기까지 차올랐을 때만 글자를 뒤집는다.
    private var dayNumberColor: Color {
        if fill > 0.74 { return onCoffee }
        return hasRecord ? theme.p.ink : theme.p.inkSoft.opacity(0.55)
    }

    /// 시간 표기는 칸 아래쪽(아래에서 약 24% 높이)에 있다. 조금만 차도 덮인다.
    private var timeColor: Color {
        fill > 0.24 ? onCoffee : theme.p.ink.opacity(0.75)
    }
}

// MARK: - 하루 상세

/// 날짜를 누르면 열리는 그날 기록.
///
/// "오늘 공부 끝"을 누른 시점의 할 일 목록과 체크 상태가 그대로 남아 있어서,
/// 그날 계획을 얼마나 해냈는지 나중에 볼 수 있다.
private struct DayDetail: View {
    let date: Date
    let seconds: TimeInterval
    let todos: [TodoItem]
    /// 그날 앉았던 구간들. 언제 시작해 언제 접었는지.
    let sessions: [StudySession]
    /// Zzz를 누른 시각. 눌렀으면 이게 마지막 구간의 끝보다 정확하다.
    let endedAt: Date?
    let inProgress: Bool
    let theme: Theme
    /// 체크는 지난 날에도 언제든 바꿀 수 있다. 글자는 못 고친다.
    let onToggle: (UUID) -> Void
    /// 잘못 잰 구간을 뺀다. 그 길이만큼 총합도 줄어든다.
    let onRemoveSession: (UUID) -> Void

    /// 구간 목록은 접어둔다. 자세히 보고 싶을 때만 편다.
    @State private var showSessions = false
    /// 마우스가 올라간 구간. 빼기 버튼은 이때만 보인다.
    @State private var hoveredSession: UUID?
    /// 한 번 누른 빼기 버튼. 한 번 더 눌러야 실제로 빠진다 — 실수로 기록을 날리지 않게.
    @State private var armedSession: UUID?

    private var doneCount: Int { todos.filter(\.done).count }

    var body: some View {
        // 팝오버 전체를 하나의 스크롤로 둔다.
        //
        // 예전에는 구간 목록에만 안쪽 스크롤을 뒀는데, 그러면 구간을 펼쳤을 때
        // 그 아래 TODO가 팝오버 밖으로 밀려나고 바깥은 안 스크롤돼서 닿을 수가 없었다.
        // 게다가 팝오버가 내용에 맞춰 커지다 화면 끝에 닿으면 옆으로 튀었다.
        // 이제 높이를 정해두고(min) 넘치면 이 스크롤 하나가 전부 받아준다.
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if !sessions.isEmpty {
                    Divider().overlay(theme.p.cardStroke)
                    clockRow
                    sessionList
                }

                if todos.isEmpty {
                    Text("적어둔 할 일이 없던 날이에요.")
                        .font(Typo.body(12.5))
                        .foregroundStyle(theme.p.inkSoft)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                } else {
                    Divider().overlay(theme.p.cardStroke)
                    list
                }
            }
        }
        .frame(width: 276, height: min(estimatedHeight, Self.maxHeight))
        .background(theme.p.card)
    }

    /// 내용 높이를 대략 잰다. 넘치면 스크롤, 모자라면 딱 맞게 줄인다.
    /// 조금 적게 잡혀도 스크롤이 받아주니 안전하다.
    private static let maxHeight: CGFloat = 460

    private var estimatedHeight: CGFloat {
        var h: CGFloat = 92                       // 머리(날짜·총시간)
        if !sessions.isEmpty {
            h += 48                               // 시작·마무리 줄
            h += 40                               // 펼치기 토글
            if showSessions { h += CGFloat(sessions.count) * 24 + 12 }
        }
        h += todos.isEmpty ? 48 : (12 + CGFloat(todos.count) * 34)
        return h
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(KoDate.short(date))
                    .font(Typo.bodyStrong(14))
                    .foregroundStyle(theme.p.ink)
                Spacer()
                if inProgress {
                    Text("진행 중")
                        .font(Typo.body(11))
                        .foregroundStyle(theme.p.brass)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TimeFormat.human(seconds))
                    .font(Typo.title(19))
                    .foregroundStyle(theme.p.ink)

                if !todos.isEmpty {
                    Text("할 일 \(doneCount)/\(todos.count)")
                        .font(Typo.body(12))
                        .foregroundStyle(theme.p.inkSoft)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: 시간대

    private var firstStart: Date? { sessions.map(\.start).min() }

    private var lastEnd: Date? {
        if let endedAt { return endedAt }
        return sessions.compactMap(\.end).max()
    }

    /// 그날 몇 시에 앉아 몇 시에 접었는지. 총 시간만으로는 안 보이는 것이다.
    private var clockRow: some View {
        HStack(spacing: 0) {
            stamp(label: "시작", value: firstStart.map(KoDate.hourMinute) ?? "—")

            Rectangle()
                .fill(theme.p.cardStroke.opacity(0.7))
                .frame(width: 1, height: 24)

            stamp(
                label: inProgress ? "지금" : "마무리",
                value: inProgress ? "재는 중" : (lastEnd.map(KoDate.hourMinute) ?? "—")
            )
        }
        .padding(.vertical, 12)
    }

    private func stamp(label: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(label)
                .font(Typo.body(10.5))
                .foregroundStyle(theme.p.inkSoft.opacity(0.85))
            Text(value)
                .font(Typo.plain(14.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.p.ink)
        }
        .frame(maxWidth: .infinity)
    }

    /// 어떻게 쪼개 앉았는지 보여준다. 한 번만 잰 날도 둔다 — 그 구간을 뺄 수 있어야 한다.
    ///
    /// **접어둔다.** 잠깐씩 여러 번 눌렀다 뗀 날은 구간이 수십 개가 되는데,
    /// 그게 다 펼쳐져 있으면 정작 보려던 시간과 할 일이 밀려난다.
    /// 평소엔 몇 번 앉았는지만 알려주고, 궁금할 때 편다.
    /// 구간 목록. 펼치면 바깥 스크롤이 통째로 받아주므로 여기엔 스크롤을 두지 않는다.
    @ViewBuilder
    private var sessionList: some View {
        Divider().overlay(theme.p.cardStroke.opacity(0.6))

        VStack(alignment: .leading, spacing: 0) {
            sessionToggle

            if showSessions {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
    }

    private var sessionToggle: some View {
        Button {
            withAnimation(Motion.button) { showSessions.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.p.inkSoft.opacity(0.7))
                    .rotationEffect(.degrees(showSessions ? 90 : 0))

                Text(sessions.count > 1 ? "\(sessions.count)번 나눠서 했어요" : "한 번에 했어요")
                    .font(Typo.body(11.5))
                    .foregroundStyle(theme.p.inkSoft)

                Spacer(minLength: 8)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))
        .help(showSessions ? "구간 접기" : "언제언제 앉았는지 보기")
    }

    private func sessionRow(_ session: StudySession) -> some View {
        let armed = armedSession == session.id
        // 재는 중인 구간은 아직 길이가 정해지지 않아 뺄 수 없다.
        let removable = !session.isOpen
        let showButton = removable && (armed || hoveredSession == session.id)

        return HStack(spacing: 8) {
            Text(KoDate.hourMinute(session.start)
                 + " – "
                 + (session.end.map(KoDate.hourMinute) ?? "…"))
                .font(Typo.plain(11.5))
                .monospacedDigit()
                .foregroundStyle(theme.p.inkSoft)

            Spacer(minLength: 8)

            Text(TimeFormat.human(session.length()))
                .font(Typo.body(11.5))
                .foregroundStyle(theme.p.inkSoft.opacity(0.85))
                .strikethrough(armed, color: theme.p.inkSoft.opacity(0.6))

            Button {
                if armed {
                    withAnimation(Motion.button) {
                        armedSession = nil
                        onRemoveSession(session.id)
                    }
                } else {
                    withAnimation(Motion.button) { armedSession = session.id }
                }
            } label: {
                Group {
                    if armed {
                        Text("빼기")
                            .font(Typo.bodyStrong(11))
                            .foregroundStyle(.red.opacity(0.85))
                    } else {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.p.inkSoft.opacity(0.8))
                    }
                }
                .frame(minWidth: 28, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.95))
            .opacity(showButton ? 1 : 0)
            .allowsHitTesting(showButton)
            .help(armed ? "한 번 더 누르면 이 구간을 빼요" : "잘못 잰 구간 빼기")
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                hoveredSession = session.id
            } else if hoveredSession == session.id {
                hoveredSession = nil
                // 다른 데로 가면 확인 상태도 풀어둔다.
                if armed { withAnimation(Motion.button) { armedSession = nil } }
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(todos) { item in
                HStack(alignment: .top, spacing: 10) {
                    InkCheckbox(
                        done: item.done,
                        tint: theme.p.done,
                        boxColor: theme.p.inkSoft,
                        size: 17
                    )
                    .padding(.top, 1)
                    .animation(Motion.ink, value: item.done)

                    Text(item.text)
                        .font(Typo.body(13))
                        .lineSpacing(3)
                        .strikethrough(item.done, color: theme.p.inkSoft.opacity(0.6))
                        .foregroundStyle(theme.p.ink.opacity(item.done ? 0.5 : 0.95))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture { onToggle(item.id) }
            }
        }
        .padding(.vertical, 6)
    }
}
