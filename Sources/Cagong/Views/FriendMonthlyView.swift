import SwiftUI

/// 친구의 월간 기록. 친구 탭에서 친구를 누르면 시트로 열린다.
///
/// 내 먼슬리와 달리 **할 일(TODO)은 보이지 않는다** — 남의 할 일 내용까지 볼 이유가
/// 없다. 날짜별 공부 시간과, 날짜를 누르면 시작·마무리 시각·구간만 나온다.
struct FriendMonthlyView: View {
    @EnvironmentObject private var friendSync: FriendSync
    @Environment(\.dismiss) private var dismiss
    let friend: Friend
    let theme: Theme

    @State private var stats: [String: DayStat] = [:]
    @State private var year: Int
    @State private var month: Int
    @State private var selectedKey: String?

    init(friend: Friend, theme: Theme) {
        self.friend = friend
        self.theme = theme
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        _year = State(initialValue: now.year ?? 2026)
        _month = State(initialValue: now.month ?? 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            board
        }
        .frame(width: 560, height: 620)
        .background(theme.p.card)
        .task { await load() }
    }

    private var titleBar: some View {
        HStack {
            Text(friend.displayName)
                .font(Typo.title(17))
                .foregroundStyle(theme.p.ink)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.p.inkSoft)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(theme.p.ink.opacity(0.06)))
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.p.cardStroke).frame(height: 1)
        }
    }

    private var board: some View {
        VStack(spacing: 0) {
            header
            summary
                .padding(.top, 16)
            weekdayRow
                .padding(.top, 18)
            grid
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
    }

    // MARK: 머리

    private var header: some View {
        HStack(spacing: 12) {
            Text("\(String(year))년 \(month)월")
                .font(Typo.title(20))
                .foregroundStyle(theme.p.ink)
            Spacer()
            HStack(spacing: 4) {
                stepButton("chevron.left") { step(-1) }
                stepButton("chevron.right", disabled: isAtCurrentMonth) { step(1) }
            }
        }
    }

    private func stepButton(_ icon: String, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(disabled ? theme.p.inkSoft.opacity(0.3) : theme.p.inkSoft)
                .frame(width: 28, height: 28)
                .background(Circle().fill(theme.p.ink.opacity(disabled ? 0 : 0.05)))
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled)
    }

    private var summary: some View {
        HStack(spacing: 0) {
            stat(label: "Total", value: TimeFormat.human(monthTotal), emphasis: true)
            divider
            stat(label: "Days", value: "\(studiedDays)일")
            divider
            stat(label: "Average", value: averageText)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { hairline }
        .overlay(alignment: .bottom) { hairline }
    }

    private var hairline: some View {
        Rectangle().fill(theme.p.cardStroke.opacity(0.8)).frame(height: 1)
    }
    private var divider: some View {
        Rectangle().fill(theme.p.cardStroke.opacity(0.7)).frame(width: 1, height: 28)
    }

    private func stat(label: String, value: String, emphasis: Bool = false) -> some View {
        VStack(spacing: 8) {
            Eyebrow(text: label, theme: theme).frame(height: 13, alignment: .bottom)
            Text(value)
                .font(emphasis ? Typo.title(21) : Typo.bodyStrong(15))
                .foregroundStyle(emphasis ? theme.p.ink : theme.p.inkSoft)
                .frame(height: 26, alignment: .center)
        }
        .frame(maxWidth: .infinity)
    }

    private var weekdayRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(KoDate.weekdaySymbols.enumerated()), id: \.offset) { idx, sym in
                Text(sym)
                    .font(Typo.body(11.5))
                    .foregroundStyle(idx == 0 ? theme.p.brass.opacity(0.9) : theme.p.inkSoft.opacity(0.75))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: 격자

    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(Array(MonthGrid.weeks(year: year, month: month).enumerated()), id: \.offset) { _, week in
                HStack(spacing: 6) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            cell(day)
                        } else {
                            Color.clear.frame(height: 58).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ day: Date) -> some View {
        let key = DateKey.string(from: day)
        let stat = stats[key]
        return DayCell(
            date: day,
            seconds: stat?.seconds ?? 0,
            goalSeconds: TimeInterval((stat?.goalMinutes ?? 0) * 60),
            inProgress: false,
            isToday: Calendar.current.isDateInToday(day),
            selected: selectedKey == key,
            theme: theme
        )
        .onTapGesture {
            guard stat != nil else { return }
            selectedKey = (selectedKey == key) ? nil : key
        }
        .popover(
            isPresented: Binding(
                get: { selectedKey == key },
                set: { if !$0, selectedKey == key { selectedKey = nil } }
            ),
            arrowEdge: .bottom
        ) {
            if let stat { FriendDayDetail(date: day, stat: stat, theme: theme) }
        }
    }

    // MARK: 계산

    private var monthPrefix: String { DateKey.monthPrefix(year: year, month: month) }
    private var monthStats: [DayStat] { stats.values.filter { $0.dayKey.hasPrefix(monthPrefix) } }
    private var monthTotal: TimeInterval { monthStats.reduce(0) { $0 + $1.seconds } }
    private var studiedDays: Int { monthStats.filter { $0.seconds > 0 }.count }
    private var averageText: String {
        guard studiedDays > 0 else { return "—" }
        return TimeFormat.human(monthTotal / Double(studiedDays))
    }

    private var isAtCurrentMonth: Bool {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        return now.year == year && now.month == month
    }

    private func step(_ delta: Int) {
        var m = month + delta, y = year
        if m > 12 { m = 1; y += 1 }
        if m < 1 { m = 12; y -= 1 }
        withAnimation(Motion.screen) { month = m; year = y }
    }

    private func load() async {
        guard let fetched = await friendSync.loadMonth(of: friend) else { return }
        stats = Dictionary(fetched.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

// MARK: - 친구 하루 상세 (할 일 없음)

/// 친구의 하루 — 시간과 구간만. 할 일은 보이지 않는다.
private struct FriendDayDetail: View {
    let date: Date
    let stat: DayStat
    let theme: Theme

    @State private var showSessions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !stat.sessions.isEmpty {
                Divider().overlay(theme.p.cardStroke)
                clockRow
                if stat.sessions.count > 1 { sessionList }
            }
        }
        .frame(width: 260)
        .background(theme.p.card)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(KoDate.short(date))
                .font(Typo.bodyStrong(14))
                .foregroundStyle(theme.p.ink)
            Text(TimeFormat.human(stat.seconds))
                .font(Typo.title(19))
                .foregroundStyle(theme.p.ink)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var clockRow: some View {
        HStack(spacing: 0) {
            stamp(label: "시작", value: stat.firstStart.map(KoDate.hourMinute) ?? "—")
            Rectangle().fill(theme.p.cardStroke.opacity(0.7)).frame(width: 1, height: 24)
            stamp(label: "마무리", value: stat.lastEnd.map(KoDate.hourMinute) ?? "—")
        }
        .padding(.vertical, 12)
    }

    private func stamp(label: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(label).font(Typo.body(10.5)).foregroundStyle(theme.p.inkSoft.opacity(0.85))
            Text(value).font(Typo.plain(14.5, weight: .semibold)).monospacedDigit()
                .foregroundStyle(theme.p.ink)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var sessionList: some View {
        Divider().overlay(theme.p.cardStroke.opacity(0.6))
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.button) { showSessions.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.p.inkSoft.opacity(0.7))
                        .rotationEffect(.degrees(showSessions ? 90 : 0))
                    Text("\(stat.sessions.count)번 나눠서 했어요")
                        .font(Typo.body(11.5))
                        .foregroundStyle(theme.p.inkSoft)
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.99))

            if showSessions {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(stat.sessions) { s in
                        HStack(spacing: 8) {
                            Text(KoDate.hourMinute(s.start) + " – " + (s.end.map(KoDate.hourMinute) ?? "…"))
                                .font(Typo.plain(11.5)).monospacedDigit()
                                .foregroundStyle(theme.p.inkSoft)
                            Spacer(minLength: 8)
                            Text(TimeFormat.human(s.length()))
                                .font(Typo.body(11.5))
                                .foregroundStyle(theme.p.inkSoft.opacity(0.85))
                        }
                    }
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
    }
}
