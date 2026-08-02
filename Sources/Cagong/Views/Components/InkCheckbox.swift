import SwiftUI

/// 체크 표시 획. 두 번 꺾이는 손글씨 체크.
struct InkCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.04))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// 눌러서 체크하는 상자.
///
/// 체크는 획이 그려지듯 나타난다(`trim` 0→1). 살짝 튕기는 스프링이라
/// "방금 내가 눌러서 됐다"는 감각이 남는다.
struct InkCheckbox: View {
    let done: Bool
    let tint: Color
    let boxColor: Color
    var size: CGFloat = 19

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint.opacity(done ? 0.13 : 0))

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(boxColor.opacity(done ? 0.3 : 0.65), lineWidth: 1.4)

            // 획이 상자 밖으로 조금 삐져나가야 손으로 그은 것처럼 보인다.
            InkCheck()
                .trim(from: 0, to: done ? 1 : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.86, height: size * 0.62)
                .offset(x: size * 0.06, y: -size * 0.06)
        }
        .frame(width: size, height: size)
        .animation(Motion.ink, value: done)
    }
}
