import SwiftUI

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

    /// 1일 앞·말일 뒤의 빈 칸. 날짜 칸과 같은 크기만 차지한다.
    static var blank: some View {
        Color.clear
            .frame(height: 58)
            .frame(maxWidth: .infinity)
    }

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
