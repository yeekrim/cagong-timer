import SwiftUI

/// 배경만 지운 음료 사진을 그대로 보여준다.
///
/// 사진에는 아무 보정도 하지 않는다 — 탈색·마스크·진행률 채우기 모두 없다.
/// 하루 목표 진행률은 시간 아래의 막대가 담당한다.
struct DrinkGlass: View {
    let theme: Theme
    let drink: Drink
    /// 정사각 캔버스 한 변. 사진은 `Tools/NormalizeDrinks`로 규격이 맞춰져 있다.
    var side: CGFloat = 150

    @ObservedObject private var library = DrinkLibrary.shared

    var body: some View {
        Group {
            if let image = library.image(for: drink) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: side, height: side)
                    .animation(Motion.card, value: drink.id)
            } else {
                fallback
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
