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

    @State private var cursor = MonthCursor.current()
    @State private var revealed = false
    /// 상세를 펼친 날짜. nil이면 닫힘.
    @State private var selectedKey: String?

    init(theme: Theme, namespace: Namespace.ID) {
        self.theme = theme
        self.namespace = namespace
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
            MonthSummary(
                total: store.monthTotal(year: cursor.year, month: cursor.month),
                days: store.monthStudiedDays(year: cursor.year, month: cursor.month),
                theme: theme
            )
                .padding(.top, 18)
            MonthWeekdayRow(theme: theme)
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
            RoundedRectangle(cornerRadius: Corner.card, style: .continuous),
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
                Text(cursor.title)
                    .font(Typo.title(21))
                    .foregroundStyle(theme.p.ink)
            }

            Spacer()

            HStack(spacing: 4) {
                MonthStepButton(systemName: "chevron.left", help: "이전 달", theme: theme) { step(-1) }
                MonthStepButton(systemName: "chevron.right", help: "다음 달",
                                disabled: cursor.isCurrent, theme: theme) { step(1) }
            }
        }
    }

    // MARK: 격자

    /// 한 달은 최대 6주라 스크롤이 필요 없다. 고정 격자로 두고,
    /// 리빌은 주 단위로 시차를 둔 등장으로 처리한다.
    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(Array(cursor.weeks.enumerated()), id: \.offset) { weekIndex, week in
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
                                isPresented: .selecting(key, in: $selectedKey),
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
                            DayCell.blank
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

    // MARK: 달 넘기기

    private func step(_ delta: Int) {
        withAnimation(Motion.screen) { cursor.step(delta) }
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

    private var clockRow: some View {
        DayClockRow(
            start: firstStart.map(KoDate.hourMinute) ?? "—",
            endLabel: inProgress ? "지금" : "마무리",
            end: inProgress ? "재는 중" : (lastEnd.map(KoDate.hourMinute) ?? "—"),
            theme: theme
        )
    }

    /// 한 번만 잰 날도 둔다 — 그 구간을 뺄 수 있어야 한다.
    ///
    /// **접어둔다.** 잠깐씩 여러 번 눌렀다 뗀 날은 구간이 수십 개가 되는데,
    /// 그게 다 펼쳐져 있으면 정작 보려던 시간과 할 일이 밀려난다.
    /// 평소엔 몇 번 앉았는지만 알려주고, 궁금할 때 편다.
    private var sessionList: some View {
        SessionSection(
            title: sessions.count > 1 ? "\(sessions.count)번 나눠서 했어요" : "한 번에 했어요",
            isExpanded: $showSessions,
            sessions: sessions,
            showsHelp: true,
            theme: theme
        ) { session in
            sessionRow(session)
        }
    }

    private func sessionRow(_ session: StudySession) -> some View {
        let armed = armedSession == session.id
        // 재는 중인 구간은 아직 길이가 정해지지 않아 뺄 수 없다.
        let removable = !session.isOpen
        let showButton = removable && (armed || hoveredSession == session.id)

        return HStack(spacing: 8) {
            SessionRangeText(session: session, theme: theme)

            Spacer(minLength: 8)

            SessionLengthText(session: session, struck: armed, theme: theme)

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
