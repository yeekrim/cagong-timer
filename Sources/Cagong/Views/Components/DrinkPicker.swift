import SwiftUI

/// 음료 고르기. 실제 잔을 그대로 축소해 보여주므로 설명이 필요 없다.
///
/// 6종이라 한 줄에 늘어놓으면 이름이 잘린다. 3칸씩 두 줄로 접는다.
struct DrinkPicker: View {
    let selected: DrinkID
    let theme: Theme
    let onSelect: (DrinkID) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Drink.all) { drink in
                chip(drink)
            }
        }
    }

    private func chip(_ drink: Drink) -> some View {
        let isOn = drink.id == selected

        return Button {
            withAnimation(Motion.card) { onSelect(drink.id) }
        } label: {
            VStack(spacing: 8) {
                DrinkGlass(
                    running: false,
                    theme: theme,
                    drink: drink,
                    side: 62,
                    compact: true
                )

                Text(drink.name)
                    .font(Typo.body(11))
                    .foregroundStyle(isOn ? theme.p.ink : theme.p.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(height: 28, alignment: .top)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(theme.p.accent.opacity(isOn ? 0.09 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                isOn ? theme.p.accent.opacity(0.6) : theme.p.cardStroke.opacity(0.55),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .help(drink.blurb)
        .accessibilityLabel("\(drink.name), \(isOn ? "선택됨" : "선택 안 됨")")
    }
}
