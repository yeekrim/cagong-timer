import SwiftUI

// MARK: - 김

/// 측정 중일 때만 올라오는 김.
///
/// 움직이면 시간이 재어지고 있고, 멈추면 멈춘 것이다. 숫자를 읽지 않아도
/// 상태가 보인다. 아이스 음료에는 김이 오르지 않는다.
struct Steam: View {
    let active: Bool
    let color: Color
    @State private var rising = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                let heights: [CGFloat] = [22, 31, 25]
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0), color.opacity(0.6), color.opacity(0)],
                            startPoint: .bottom, endPoint: .top
                        )
                    )
                    .frame(width: 4.5, height: heights[i])
                    .blur(radius: 1.6)
                    .scaleEffect(y: rising ? 1.4 : 0.6, anchor: .bottom)
                    .offset(y: rising ? -13 : 5)
                    .opacity(rising ? 0 : 0.95)
                    .animation(
                        active
                        ? .easeOut(duration: 2.6).repeatForever(autoreverses: false).delay(Double(i) * 0.6)
                        : nil,
                        value: rising
                    )
            }
        }
        .opacity(active ? 1 : 0)
        .animation(Motion.card, value: active)
        .onAppear { rising = true }
        .allowsHitTesting(false)
    }
}

// MARK: - 음료 잔

/// 배경만 지운 음료 사진을 그대로 보여준다.
///
/// 사진에는 아무 보정도 하지 않는다 — 탈색·마스크·진행률 채우기 모두 없다.
/// 하루 목표 진행률은 시간 아래의 막대가 담당한다.
struct DrinkGlass: View {
    let running: Bool
    let theme: Theme
    let drink: Drink
    /// 정사각 캔버스 한 변. 사진은 `Tools/NormalizeDrinks`로 규격이 맞춰져 있다.
    var side: CGFloat = 150
    /// 작게 놓을 때는 김을 뺀다.
    var compact: Bool = false

    @ObservedObject private var library = DrinkLibrary.shared

    /// 캔버스 위쪽에서 잔이 시작되지 않는 비율. 김이 올라올 자리다.
    /// `NormalizeDrinks`의 캔버스(640)와 내용 높이(516)에서 나온 값이다.
    private static let headroom: CGFloat = (640 - 516 - 6) / 640

    var body: some View {
        ZStack(alignment: .top) {
            if let image = library.image(for: drink) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: side, height: side)
                    .animation(Motion.card, value: drink.id)
            } else {
                fallback
            }

            // 김은 캔버스 위쪽 여백 안에 겹쳐 그린다.
            // 위로 쌓으면 그만큼 잔이 아래로 밀려 내려간다.
            if !compact {
                Steam(active: running && drink.hot, color: theme.p.accentSoft)
                    .frame(height: side * Self.headroom * 0.8)
                    .padding(.top, side * 0.01)
            }
        }
        .frame(width: side, height: side)
        .accessibilityLabel(drink.name)
    }

    /// 사진을 못 읽었을 때. 화면이 비어 보이지 않게 최소한의 표시는 남긴다.
    private var fallback: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(theme.p.ink.opacity(0.08))
            .frame(width: side * 0.5, height: side * 0.6)
            .overlay(
                Text(drink.name)
                    .font(Typo.body(10))
                    .foregroundStyle(theme.p.inkSoft)
                    .padding(4)
            )
            .frame(width: side, height: side, alignment: .bottom)
    }
}
