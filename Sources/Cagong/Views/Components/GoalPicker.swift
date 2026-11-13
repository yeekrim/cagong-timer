import SwiftUI

/// 그날치 목표 정하기. 타이머 화면의 목표 문구를 누르면 열린다.
///
/// 그날치 목표만 바꾼다. 다른 날은 건드리지 않는다.
struct GoalPicker: View {
    @ObservedObject var store: StudyStore
    let theme: Theme

    private var measuringDate: Date {
        DateKey.date(from: store.measuringKey) ?? Date()
    }

    var body: some View {
        let minutes = store.goalMinutes(for: store.measuringKey)

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(KoDate.dayWithWeekday(measuringDate)) 목표")
                    .font(Typo.bodyStrong(13))
                    .foregroundStyle(theme.p.ink)
                Text("이 날에만 적용됩니다")
                    .font(Typo.body(11))
                    .foregroundStyle(theme.p.inkSoft.opacity(0.8))
            }

            HStack {
                Text(TimeFormat.goal(minutes: minutes))
                    .font(Typo.title(19))
                    .foregroundStyle(theme.p.ink)
                    .contentTransition(.numericText())
                    .animation(Motion.digit, value: minutes)

                Spacer()

                HStack(spacing: 6) {
                    goalStep("minus", to: minutes - 30)
                    goalStep("plus", to: minutes + 30)
                }
            }

            Slider(
                value: Binding(
                    get: { Double(minutes) },
                    set: { store.setGoal(minutes: Int(($0 / 30).rounded()) * 30) }
                ),
                in: 30...720,
                step: 30
            )
            .tint(theme.p.accent)
        }
        .padding(18)
        .frame(width: 288)
        .background(theme.p.card)
    }

    private func goalStep(_ icon: String, to minutes: Int) -> some View {
        Button {
            withAnimation(Motion.button) { store.setGoal(minutes: minutes) }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.p.inkSoft)
                .frame(width: 25, height: 25)
                .background(Circle().fill(theme.p.ink.opacity(0.07)))
        }
        .buttonStyle(PressableStyle())
    }
}
