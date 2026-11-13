import SwiftUI

/// 기록할 날짜 고르기. 타이머 화면의 날짜 칩을 누르면 열린다.
///
/// 오늘과 어제만. 그저께부터는 아예 선택지에 없다.
struct MeasuringDatePicker: View {
    @ObservedObject var store: StudyStore
    let theme: Theme
    /// 고르고 나면 팝오버를 닫는다.
    let onPicked: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([DateKey.today(), DateKey.yesterday()], id: \.self) { key in
                let isOn = key == store.measuringKey
                let date = DateKey.date(from: key) ?? Date()

                Button {
                    withAnimation(Motion.screen) { store.setMeasuringDate(key) }
                    onPicked()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(isOn ? theme.p.accent : theme.p.inkSoft.opacity(0.5))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(key == DateKey.today() ? "오늘" : "어제")
                                .font(Typo.bodyStrong(13))
                                .foregroundStyle(theme.p.ink)
                            Text(KoDate.dayWithWeekday(date))
                                .font(Typo.body(11.5))
                                .foregroundStyle(theme.p.inkSoft)
                        }

                        Spacer(minLength: 20)

                        Text(TimeFormat.human(store.seconds(for: key)))
                            .font(Typo.stamp(12))
                            .foregroundStyle(theme.p.inkSoft)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }

            Text("그제부터는 고칠 수 없어요.")
                .font(Typo.body(11))
                .foregroundStyle(theme.p.inkSoft.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
        .frame(width: 250)
        .background(theme.p.card)
    }
}
