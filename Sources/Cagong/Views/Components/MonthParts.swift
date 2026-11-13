import SwiftUI

// 내 먼슬리(MonthlyView)와 친구 먼슬리(FriendMonthlyView)가 같이 쓰는 조각들.
// 두 화면은 크기와 움직임이 조금 다르다. 그 차이는 `compact`·`showsHelp`로 남겨 둔다.

// MARK: - 보고 있는 달

/// 먼슬리가 보고 있는 연·월.
struct MonthCursor: Equatable {
    var year: Int
    var month: Int

    /// 이번 달
    static func current() -> MonthCursor {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        return MonthCursor(year: now.year ?? 2026, month: now.month ?? 1)
    }

    /// 이번 달이면 더 앞으로 갈 수 없다.
    var isCurrent: Bool {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        return now.year == year && now.month == month
    }

    /// "2026년 7월"
    var title: String { "\(String(year))년 \(month)월" }

    var weeks: [[Date?]] { MonthGrid.weeks(year: year, month: month) }

    /// 한 달씩 앞뒤로. 해가 바뀌면 연도도 넘긴다.
    mutating func step(_ delta: Int) {
        var m = month + delta
        var y = year
        if m > 12 { m = 1; y += 1 }
        if m < 1 { m = 12; y -= 1 }
        month = m
        year = y
    }
}

// MARK: - 머리

/// 이전·다음 달 버튼.
struct MonthStepButton: View {
    let systemName: String
    /// 마우스를 올렸을 때 설명. 친구 먼슬리는 두지 않는다.
    var help: String? = nil
    var disabled = false
    let theme: Theme
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        let button = Button(action: action) {
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

        if let help { button.help(help) } else { button }
    }
}

// MARK: - 요약

/// Total · Days · Average 한 줄.
///
/// 회색 박스로 감싸면 "큰 숫자 + 작은 라벨" 템플릿이 된다.
/// 위아래 헤어라인만 남겨 숫자가 종이 위에 바로 놓이게 한다.
struct MonthSummary: View {
    let total: TimeInterval
    let days: Int
    let theme: Theme
    /// 친구 먼슬리(시트)용. 조금 작게, 숫자 바뀜 애니메이션 없이 그린다.
    var compact = false

    private var averageText: String {
        guard days > 0 else { return "—" }
        return TimeFormat.human(total / Double(days))
    }

    var body: some View {
        HStack(spacing: 0) {
            stat(label: "Total", value: TimeFormat.human(total), emphasis: true)
            divider
            stat(label: "Days", value: "\(days)일")
            divider
            stat(label: "Average", value: averageText)
        }
        .padding(.vertical, compact ? 16 : 18)
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
            .frame(width: 1, height: compact ? 28 : 30)
    }

    /// 값의 글자 크기가 서로 달라서, 높이를 고정하지 않으면 라벨 줄이 어긋난다.
    @ViewBuilder
    private func stat(label: String, value: String, emphasis: Bool = false) -> some View {
        let column = VStack(spacing: 8) {
            Eyebrow(text: label, theme: theme)
                .frame(height: 13, alignment: .bottom)

            valueText(value, emphasis: emphasis)
        }
        .frame(maxWidth: .infinity)

        if compact { column } else { column.animation(Motion.digit, value: value) }
    }

    @ViewBuilder
    private func valueText(_ value: String, emphasis: Bool) -> some View {
        let text = Text(value)
            .font(emphasis ? Typo.title(compact ? 21 : 22) : Typo.bodyStrong(15))
            .foregroundStyle(emphasis ? theme.p.ink : theme.p.inkSoft)

        if compact {
            text.frame(height: 26, alignment: .center)
        } else {
            text
                .contentTransition(.numericText())
                .frame(height: 28, alignment: .center)
        }
    }
}

// MARK: - 요일

/// 일~토. 일요일만 놋쇠색.
struct MonthWeekdayRow: View {
    let theme: Theme

    var body: some View {
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
}

// MARK: - 날짜 선택

extension Binding where Value == Bool {
    /// `selection`이 `key`일 때 열려 있는 팝오버. 닫히면 선택을 비운다 —
    /// 단, 그 사이 다른 칸이 선택됐으면 건드리지 않는다.
    static func selecting(_ key: String, in selection: Binding<String?>) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue == key },
            set: { if !$0, selection.wrappedValue == key { selection.wrappedValue = nil } }
        )
    }
}

// MARK: - 하루 상세: 시작·마무리

/// 그날 몇 시에 앉아 몇 시에 접었는지. 총 시간만으로는 안 보이는 것이다.
struct DayClockRow: View {
    let start: String
    let endLabel: String
    let end: String
    let theme: Theme

    var body: some View {
        HStack(spacing: 0) {
            stamp(label: "시작", value: start)

            Rectangle()
                .fill(theme.p.cardStroke.opacity(0.7))
                .frame(width: 1, height: 24)

            stamp(label: endLabel, value: end)
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
}

// MARK: - 하루 상세: 구간 목록

/// 어떻게 쪼개 앉았는지. **접어둔다** — 펼치기 줄을 누를 때만 구간이 보인다.
/// 펼치면 바깥(팝오버)이 받아주므로 여기엔 스크롤을 두지 않는다.
struct SessionSection<Row: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let sessions: [StudySession]
    /// 펼치기 줄에 설명을 붙일지. 친구 먼슬리는 두지 않는다.
    var showsHelp = false
    let theme: Theme
    @ViewBuilder let row: (StudySession) -> Row

    var body: some View {
        Divider().overlay(theme.p.cardStroke.opacity(0.6))

        VStack(alignment: .leading, spacing: 0) {
            toggle

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sessions) { session in
                        row(session)
                    }
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
    }

    @ViewBuilder
    private var toggle: some View {
        let button = Button {
            withAnimation(Motion.button) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.p.inkSoft.opacity(0.7))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Text(title)
                    .font(Typo.body(11.5))
                    .foregroundStyle(theme.p.inkSoft)

                Spacer(minLength: 8)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.99))

        if showsHelp {
            button.help(isExpanded ? "구간 접기" : "언제언제 앉았는지 보기")
        } else {
            button
        }
    }
}

/// 구간의 시각 범위. "09:00 – 09:50", 재는 중이면 "09:00 – …"
struct SessionRangeText: View {
    let session: StudySession
    let theme: Theme

    var body: some View {
        Text(KoDate.hourMinute(session.start)
             + " – "
             + (session.end.map(KoDate.hourMinute) ?? "…"))
            .font(Typo.plain(11.5))
            .monospacedDigit()
            .foregroundStyle(theme.p.inkSoft)
    }
}

/// 구간 길이. "50분"
struct SessionLengthText: View {
    let session: StudySession
    /// 빼기를 한 번 누른 구간은 줄을 긋는다.
    var struck = false
    let theme: Theme

    var body: some View {
        Text(TimeFormat.human(session.length()))
            .font(Typo.body(11.5))
            .foregroundStyle(theme.p.inkSoft.opacity(0.85))
            .strikethrough(struck, color: theme.p.inkSoft.opacity(0.6))
    }
}
