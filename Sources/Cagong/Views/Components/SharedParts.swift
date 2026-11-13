import SwiftUI

// 여러 화면이 같이 쓰는 작은 조각들. 크기가 화면마다 다르면 인자로 받는다.

// MARK: - 친구 아바타

/// 이름 첫 글자를 담은 동그라미. 이름이 비었으면 "?".
struct FriendAvatar: View {
    let name: String
    let size: CGFloat
    let fontSize: CGFloat
    let theme: Theme

    var body: some View {
        Circle()
            .fill(theme.p.accent.opacity(0.15))
            .frame(width: size, height: size)
            .overlay(
                Text(name.isEmpty ? "?" : String(name.prefix(1)))
                    .font(Typo.bodyStrong(fontSize))
                    .foregroundStyle(theme.p.accent)
            )
    }
}

// MARK: - 진행 막대

/// 목표까지 얼마나 왔는지. 높이 4의 캡슐. 폭은 바깥에서 정한다.
struct ProgressCapsule: View {
    /// 0...1
    let progress: Double
    let theme: Theme

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(theme.p.ink.opacity(theme.isDark ? 0.16 : 0.08))
                .frame(height: 4)

            GeometryReader { g in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [theme.p.accentSoft, theme.p.accent],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: g.size.width * progress, height: 4)
            }
            .frame(height: 4)
        }
    }
}

// MARK: - 시트 제목 줄

/// 시트 맨 위의 제목과 닫기 버튼. Esc로도 닫힌다.
struct SheetTitleBar: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let theme: Theme
    /// 제목 줄 아래 여백. 시트마다 조금 다르다.
    var bottomPadding: CGFloat = 16

    var body: some View {
        HStack {
            Text(title)
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
        .padding(.bottom, bottomPadding)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.p.cardStroke).frame(height: 1)
        }
    }
}

// MARK: - 알약 탭

/// 고른 탭 뒤로 강조색 알약이 미끄러져 따라간다(matchedGeometryEffect).
struct PillTabLabel: View {
    let text: String
    let selected: Bool
    /// 탭을 같은 폭으로 나눠 채울지(설정), 글자 폭에 맞출지(상단 바).
    var stretches = false
    let pillID: String
    let namespace: Namespace.ID
    let theme: Theme

    var body: some View {
        sized
            .padding(.vertical, 7)
            .background {
                if selected {
                    Capsule()
                        .fill(theme.p.accent)
                        .matchedGeometryEffect(id: pillID, in: namespace)
                }
            }
    }

    @ViewBuilder
    private var sized: some View {
        let label = Text(text)
            .font(Typo.bodyStrong(13))
            .foregroundStyle(selected ? theme.onAccent : theme.p.inkSoft)

        if stretches {
            label.frame(maxWidth: .infinity)
        } else {
            label.padding(.horizontal, 17)
        }
    }
}
