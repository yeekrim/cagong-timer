import SwiftUI

/// 히어로 시간 표시.
///
/// 글자마다 폭을 고정해서 초가 바뀔 때 레이아웃이 흔들리지 않게 한다.
/// 바뀐 자리만 `numericText`로 굴러가고, 오버슈트는 죽여서 읽기를 방해하지 않는다.
struct TimeDisplay: View {
    let seconds: TimeInterval
    var size: CGFloat = 80
    let color: Color
    let colonColor: Color

    private var chars: [Character] { Array(TimeFormat.clock(seconds)) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(chars.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(Typo.numerals(size))
                    .foregroundStyle(ch == ":" ? colonColor : color)
                    .frame(width: ch == ":" ? size * 0.30 : size * 0.60)
                    .contentTransition(.numericText())
            }
        }
        .animation(Motion.digit, value: Int(seconds))
        .accessibilityLabel("공부한 시간 \(TimeFormat.human(seconds))")
    }
}
