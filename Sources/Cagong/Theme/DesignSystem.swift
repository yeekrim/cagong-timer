import SwiftUI
import AppKit

// MARK: - 타이포그래피
//
// 시스템 글꼴 하나로 통일한다.
//
// 예전에는 라틴 글자와 숫자를 American Typewriter가 맡았다. 큰 숫자 한둘에는
// 멋이었지만, 먼슬리처럼 작은 숫자가 30개 넘게 깔리는 면에서는 읽기 힘들었다.
// 한글은 대응하는 꼴이 없어 따로 갈라 써야 했고, 그래서 한 화면 안에서 두 인상이
// 어긋났다.
//
// 지금은 전부 `.system`이다. 한글은 시스템 폴백이 Apple SD Gothic Neo로 받으므로
// 한글 꼴 자체는 예전과 같고, 숫자와 라틴만 담백해진다.
//
// 이름은 그대로 둔다 — 호출부가 "여기는 히어로 숫자", "여기는 작은 라벨"이라고
// 말하고 있어서, 무게만 여기서 갈아끼우면 된다.

enum Typo {
    /// 모든 글자의 바탕. 무게를 직접 고를 때 쓴다.
    static func plain(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// 히어로 숫자.
    ///
    /// 자리폭은 `TimeDisplay`가 글자마다 직접 고정한다(숫자 0.60 em, 콜론 0.30 em).
    /// 시스템 숫자는 0.651 em으로 타이프라이터(0.655 em)와 거의 같아서
    /// 카드 폭 계산(4.2 × 글자크기)이 그대로 유효하다.
    static func numerals(_ size: CGFloat) -> Font { plain(size, weight: .bold) }

    /// 라틴 소제목·연도·월 표기
    static func stamp(_ size: CGFloat) -> Font { plain(size, weight: .semibold) }

    /// 작은 라벨. 대문자 + 자간을 넓혀 쓴다.
    static func label(_ size: CGFloat) -> Font { plain(size, weight: .medium) }

    /// 제목
    static func title(_ size: CGFloat) -> Font { plain(size, weight: .bold) }

    /// 본문
    static func body(_ size: CGFloat) -> Font { plain(size) }

    static func bodyStrong(_ size: CGFloat) -> Font { plain(size, weight: .semibold) }
}

// MARK: - 모션
//
// 2026년 모션 트렌드의 핵심은 선형 easing을 버리고 스프링으로 가는 것,
// 그리고 물체마다 질량을 다르게 주는 것이다. 버튼은 가볍고 즉각적으로,
// 카드는 무거워서 느리게 뜬다. 아래 토큰이 그 차이를 담는다.

enum Motion {
    /// 버튼 — 가볍다. 빠르게 튀고 살짝 오버슈트.
    static let button = Animation.spring(response: 0.26, dampingFraction: 0.58)

    /// 카드 — 질량이 있다. 버튼보다 두 배 느리게 움직인다.
    static let card = Animation.spring(response: 0.55, dampingFraction: 0.82)

    /// 화면 전환 — 안정적으로 자리 잡는다. 오버슈트 없음.
    static let screen = Animation.spring(response: 0.48, dampingFraction: 0.9)

    /// 체크 잉크 — 손으로 그은 듯 튕긴다.
    static let ink = Animation.spring(response: 0.34, dampingFraction: 0.55)

    /// 숫자 굴림 — 흔들리면 읽기 힘들므로 오버슈트를 죽인다.
    static let digit = Animation.spring(response: 0.3, dampingFraction: 0.95)

    /// 메모지가 붙고 떨어지는 움직임
    static let paper = Animation.spring(response: 0.42, dampingFraction: 0.68)
}

// MARK: - 유리 표면

/// 창이 비활성일 때도 유리를 유지하는 배경.
///
/// macOS 머티리얼은 기본값이 `.followsWindowActiveState`라, 다른 앱으로 포커스가
/// 넘어가면 vibrancy를 끄고 불투명하게 굳는다. SwiftUI의 `Material`로는 이 동작을
/// 바꿀 수 없어서 `NSVisualEffectView`를 직접 쓰고 `state = .active`로 못 박는다.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    /// 배경 사진이 같은 창 안에 있으므로 창 **안쪽** 내용과 섞는다.
    /// `.behindWindow`로 두면 앱 뒤의 바탕화면을 흐리게 되어 엉뚱해진다.
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.state = .active
    }
}

/// 애플식 글래스.
///
/// 핵심은 색을 두껍게 입히는 게 아니라 세 가지다.
///   1. 뒤를 흐리고 채도를 올리는 **머티리얼** — 배경이 비쳐야 유리다
///   2. 위쪽 가장자리가 밝고 아래로 사라지는 **1px 반사광 테두리** — 유리의 두께가 여기서 읽힌다
///   3. 가깝고 부드러운 **그림자** — 멀고 진한 그림자는 유리가 아니라 판때기로 보인다
///
/// 모양을 인자로 받으므로 사각형·원·알약 어디에나 같은 규칙으로 쓸 수 있다.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var material: NSVisualEffectView.Material = .hudWindow
    /// 사진이 어두워도 글자가 읽히도록 얹는 옅은 바탕. 큰 면에만 쓴다.
    var tint: Color? = nil
    var tintOpacity: Double = 0.18
    var lifted: Bool = false

    func body(content: Content) -> some View {
        // 유리 배경은 아래에서 `allowsHitTesting(false)`로 빠진다. 그대로 두면
        // 유리 위의 빈 곳이 클릭도 마우스오버도 못 받는다 — 카드가 떠오르는 반응이
        // 글자 위에서만 일어난다. 그래서 유리 모양 그대로 클릭 영역을 되돌려준다.
        content
            .contentShape(shape)
            .background {
                ZStack {
                    VisualEffectBackground(material: material)
                        .clipShape(shape)
                        .shadow(
                            color: .black.opacity(lifted ? 0.26 : 0.17),
                            radius: lifted ? 22 : 13,
                            x: 0,
                            y: lifted ? 11 : 6
                        )

                    if let tint {
                        shape.fill(tint.opacity(tintOpacity))
                    }

                    // 유리 안쪽 위에서 떨어지는 빛
                    shape
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.14), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .blendMode(.plusLighter)

                    // 가장자리 반사광. 좌상단이 밝고 우하단으로 사라진다.
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.62),
                                .white.opacity(0.16),
                                .white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func glass<S: InsettableShape>(
        _ shape: S,
        material: NSVisualEffectView.Material = .hudWindow,
        tint: Color? = nil,
        tintOpacity: Double = 0.18,
        lifted: Bool = false
    ) -> some View {
        modifier(GlassSurface(
            shape: shape,
            material: material,
            tint: tint,
            tintOpacity: tintOpacity,
            lifted: lifted
        ))
    }
}

// MARK: - 버튼 스타일

/// 누르면 실제로 눌리는 느낌. 트렌드 문서가 말하는 "확인을 주는 마이크로 인터랙션".
///
/// `contentShape`가 핵심이다. SwiftUI는 기본적으로 **그려진 것**만 클릭 영역으로 잡는다.
/// 여백(`padding`)이나 지정한 크기(`frame`)는 포함되지 않고, 유리 배경은
/// `allowsHitTesting(false)`라 아예 빠진다. 그래서 이걸 안 걸면 38×38 화살표 버튼에서
/// 실제로 눌리는 곳은 가운데 chevron 글리프뿐이고, 사용자는 "버튼이 씹힌다"고 느낀다.
///
/// 여기 한 곳에 걸어두면 이 스타일을 쓰는 모든 버튼이 **보이는 만큼 전부** 눌린다.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.button, value: configuration.isPressed)
    }
}

/// 주 동작 버튼 — 채워진 알약.
struct PrimaryButtonStyle: ButtonStyle {
    let theme: Theme
    var wide: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.bodyStrong(15))
            .foregroundStyle(theme.isDark ? Color(hex: 0x14161E) : .white)
            .padding(.horizontal, wide ? 34 : 24)
            .padding(.vertical, 12)
            .background(
                Capsule().fill(theme.p.accent)
                    .shadow(color: theme.p.accent.opacity(0.35), radius: configuration.isPressed ? 4 : 12, y: configuration.isPressed ? 1 : 5)
            )
            // 알약 모양 그대로 눌린다. 글자만이 아니라.
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.button, value: configuration.isPressed)
    }
}

/// 보조 동작 버튼 — 외곽선만.
struct GhostButtonStyle: ButtonStyle {
    let theme: Theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.body(14))
            .foregroundStyle(theme.p.ink.opacity(configuration.isPressed ? 0.6 : 0.85))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .glass(Capsule())
            // 유리 배경은 클릭을 안 받으므로 여기서 알약 전체를 클릭 영역으로 되돌린다.
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.button, value: configuration.isPressed)
    }
}

// MARK: - 작은 라벨

/// 대문자 + 넓은 자간의 머리 라벨. 구조를 알려주는 역할만 한다.
struct Eyebrow: View {
    let text: String
    let theme: Theme
    var color: Color? = nil

    var body: some View {
        Text(text.uppercased())
            .font(Typo.label(11))
            .tracking(2.2)
            .foregroundStyle(color ?? theme.p.inkSoft)
    }
}
