import SwiftUI

// MARK: - 결정적 난수
//
// 종이 결이 매 렌더마다 바뀌면 안 된다. 고정 시드로 한 번만 생성한다.

private struct Seeded: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed | 1 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - 배경 진입점

struct ThemeBackground: View {
    let theme: Theme
    /// 동작 줄이기 설정이 켜져 있으면 false로 넘어온다.
    var animate: Bool = true
    /// 사진 장면에서 어떤 사진을 쓸지. nil이면 목록의 첫 장면.
    var photoSceneID: String? = nil

    var body: some View {
        ZStack {
            theme.p.backdrop

            switch theme.scene {
            case .paper:
                PaperScene(theme: theme)
            case .lamp:
                LampScene(theme: theme, animate: animate)
            case .photo:
                PhotoBackgroundScene(
                    scene: PhotoLibrary.shared.scene(id: photoSceneID),
                    theme: theme
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 종이 장면

/// 크래프트 종이 위. 미세한 결과 은은한 비네트만.
private struct PaperScene: View {
    let theme: Theme

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [.white.opacity(theme.isDark ? 0.04 : 0.5), .clear],
                center: .init(x: 0.5, y: 0.1),
                startRadius: 0,
                endRadius: 780
            )
            PaperGrain(color: theme.p.ink, intensity: 0.035)
            RadialGradient(
                colors: [.clear, .black.opacity(0.12)],
                center: .center,
                startRadius: 320,
                endRadius: 880
            )
        }
    }
}

/// 종이 결. 고정 시드로 뿌린 점을 한 장의 텍스처로 굽는다.
private struct PaperGrain: View {
    let color: Color
    let intensity: Double

    var body: some View {
        Canvas { ctx, size in
            var rng = Seeded(seed: 20260730)
            for _ in 0..<620 {
                let x = Double.random(in: 0...size.width, using: &rng)
                let y = Double.random(in: 0...size.height, using: &rng)
                let r = Double.random(in: 0.4...1.5, using: &rng)
                let a = Double.random(in: 0.25...1.0, using: &rng) * intensity
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(color.opacity(a))
                )
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

// MARK: - 스탠드 장면

/// 불 끈 방에 스탠드 하나. 위에서 앰버 빛이 떨어지고 아주 느리게 숨 쉰다.
private struct LampScene: View {
    let theme: Theme
    let animate: Bool
    @State private var breathing = false

    var body: some View {
        ZStack {
            EllipticalGradient(
                colors: [theme.p.accent.opacity(0.30), theme.p.accent.opacity(0.07), .clear],
                center: .init(x: 0.5, y: -0.05),
                startRadiusFraction: 0,
                endRadiusFraction: breathing ? 0.82 : 0.72
            )
            .blur(radius: 30)
            .animation(
                animate ? .easeInOut(duration: 7).repeatForever(autoreverses: true) : nil,
                value: breathing
            )

            PaperGrain(color: .white, intensity: 0.03)

            RadialGradient(
                colors: [.clear, .black.opacity(0.5)],
                center: .init(x: 0.5, y: 0.35),
                startRadius: 260,
                endRadius: 820
            )
        }
        .onAppear { breathing = true }
    }
}

// MARK: - 테마 미리보기

/// 설정에서 쓰는 테마 미리보기.
///
/// 작은 프레임에 배경을 직접 그리면 그라디언트와 결이 보이지 않는다.
/// 큰 크기로 그린 뒤 축소하고, 대표 요소(종이 카드·메모지·포인트 색)를 얹어
/// 어떤 테마인지 한눈에 구분되게 한다.
struct ThemePreview: View {
    let theme: Theme
    var width: CGFloat = 74
    var height: CGFloat = 48

    private var scale: CGFloat { width / 320 }

    var body: some View {
        ZStack {
            ThemeBackground(theme: theme, animate: false)
                .frame(width: 320, height: 320 * (height / width))
                .scaleEffect(scale, anchor: .center)
                .frame(width: width, height: height)
                .clipped()

            HStack(spacing: width * 0.055) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.p.card)
                    .frame(width: width * 0.35, height: height * 0.38)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(theme.p.memo)
                    .frame(width: width * 0.16, height: height * 0.34)
                    .rotationEffect(.degrees(-4))

                Circle()
                    .fill(theme.p.accent)
                    .frame(width: width * 0.095, height: width * 0.095)
            }
        }
        .frame(width: width, height: height)
    }
}
