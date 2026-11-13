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
    @State private var cursor = MonthCursor.current()
    @State private var selectedKey: String?

    init(friend: Friend, theme: Theme) {
        self.friend = friend
        self.theme = theme
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
            MonthSummary(total: monthTotal, days: studiedDays, theme: theme, compact: true)
                .padding(.top, 16)
            MonthWeekdayRow(theme: theme)
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
            Text(cursor.title)
                .font(Typo.title(20))
                .foregroundStyle(theme.p.ink)
            Spacer()
            HStack(spacing: 4) {
                MonthStepButton(systemName: "chevron.left", theme: theme) { step(-1) }
                MonthStepButton(systemName: "chevron.right", disabled: cursor.isCurrent, theme: theme) { step(1) }
            }
        }
    }

    // MARK: 격자

    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(Array(cursor.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 6) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            cell(day)
                        } else {
                            DayCell.blank
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
            isPresented: .selecting(key, in: $selectedKey),
            arrowEdge: .bottom
        ) {
            if let stat { FriendDayDetail(date: day, stat: stat, theme: theme) }
        }
    }

    // MARK: 계산

    private var monthPrefix: String { DateKey.monthPrefix(year: cursor.year, month: cursor.month) }
    private var monthStats: [DayStat] { stats.values.filter { $0.dayKey.hasPrefix(monthPrefix) } }
    private var monthTotal: TimeInterval { monthStats.reduce(0) { $0 + $1.seconds } }
    private var studiedDays: Int { monthStats.filter { $0.seconds > 0 }.count }

    private func step(_ delta: Int) {
        withAnimation(Motion.screen) { cursor.step(delta) }
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
        DayClockRow(
            start: stat.firstStart.map(KoDate.hourMinute) ?? "—",
            endLabel: "마무리",
            end: stat.lastEnd.map(KoDate.hourMinute) ?? "—",
            theme: theme
        )
    }

    private var sessionList: some View {
        SessionSection(
            title: "\(stat.sessions.count)번 나눠서 했어요",
            isExpanded: $showSessions,
            sessions: stat.sessions,
            theme: theme
        ) { s in
            HStack(spacing: 8) {
                SessionRangeText(session: s, theme: theme)
                Spacer(minLength: 8)
                SessionLengthText(session: s, theme: theme)
            }
        }
    }
}
