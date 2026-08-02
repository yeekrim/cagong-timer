import SwiftUI

// MARK: - Color(hex:)

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - 테마 식별자

enum ThemeID: String, Codable, CaseIterable, Identifiable {
    case photoCafe
    case cafe
    case midnight

    var id: String { rawValue }
}

/// 배경에 깔리는 장면.
enum ThemeScene {
    /// 종이 질감의 평면 배경
    case paper
    /// 위에서 스탠드 조명이 떨어지는 어두운 방
    case lamp
    /// 실제 사진
    case photo

    /// 배경이 사진인지. 사진 위에서는 카드를 손그림 테두리로 바꾸고,
    /// 상단 바 요소도 흰 박스 처리로 바꿔 읽히게 한다.
    var isPhoto: Bool { self == .photo }
}

// MARK: - 팔레트

struct Palette {
    /// 배경 기본색 (장면이 있으면 그 아래 깔리는 색)
    var backdrop: Color
    /// 종이 카드
    var card: Color
    var cardStroke: Color
    /// 본문 잉크
    var ink: Color
    var inkSoft: Color
    /// 주 동작 색
    var accent: Color
    var accentSoft: Color
    /// 숫자·강조에 쓰는 금속색
    var brass: Color
    /// 완료 표시
    var done: Color
    /// 메모지
    var memo: Color
    var memoInk: Color
    /// 메모지를 붙이는 테이프
    var tape: Color
    /// 카드 그림자 세기
    var shadow: Double
}

// MARK: - 테마

struct Theme: Identifiable {
    let id: ThemeID
    /// 설정 화면에 보이는 이름
    let name: String
    /// 한 줄 설명
    let blurb: String
    let scene: ThemeScene
    let isDark: Bool
    let p: Palette

    var colorScheme: ColorScheme { isDark ? .dark : .light }

    static func by(_ id: ThemeID) -> Theme {
        all.first { $0.id == id } ?? all[0]
    }

    /// 목록 순서 = 설정에 보이는 순서. 첫 항목이 기본값이다.
    static let all: [Theme] = [photoCafe, cafe, midnight]

    // MARK: 사진 카페 — 기본

    /// 실제 사진 배경. 그 위에는 검은 손그림 테두리의 흰 종이만 올린다.
    /// 사진 밝기가 장면마다 달라도 흰 종이는 어디서나 읽힌다.
    static let photoCafe = Theme(
        id: .photoCafe,
        name: "사진 카페",
        blurb: "실제 카페 사진 위에서. 좌우로 장면을 넘긴다.",
        scene: .photo,
        isDark: false,
        p: Palette(
            backdrop: Color(hex: 0x1B1815),
            card: Color(hex: 0xFFFFFF),
            cardStroke: Color(hex: 0x1A1713),
            ink: Color(hex: 0x14110D),
            inkSoft: Color(hex: 0x6A645B),
            accent: Color(hex: 0xC0492A),
            accentSoft: Color(hex: 0xD97B4F),
            brass: Color(hex: 0xC08E24),
            done: Color(hex: 0x3C7A4E),
            memo: Color(hex: 0xFCF6E4),
            memoInk: Color(hex: 0x1E1A14),
            tape: Color(hex: 0xDCD5C4),
            shadow: 0.4
        )
    )

    // MARK: 웜 카페

    static let cafe = Theme(
        id: .cafe,
        name: "웜 카페",
        blurb: "크래프트 종이와 에스프레소. 창가 자리의 오후.",
        scene: .paper,
        isDark: false,
        p: Palette(
            backdrop: Color(hex: 0xEBE1CE),
            card: Color(hex: 0xFCF8EF),
            cardStroke: Color(hex: 0xD9CBB0),
            ink: Color(hex: 0x2C1E15),
            inkSoft: Color(hex: 0x7A6650),
            accent: Color(hex: 0x7A4A28),
            accentSoft: Color(hex: 0xA9764C),
            brass: Color(hex: 0xB0842F),
            done: Color(hex: 0x5C7355),
            memo: Color(hex: 0xF6E4AE),
            memoInk: Color(hex: 0x3A2A1C),
            tape: Color(hex: 0xE0D2B6),
            shadow: 0.16
        )
    )

    // MARK: 심야 스탠드

    static let midnight = Theme(
        id: .midnight,
        name: "심야 스탠드",
        blurb: "불 끄고 스탠드 하나만. 앰버 조명이 번지는 책상.",
        scene: .lamp,
        isDark: true,
        p: Palette(
            backdrop: Color(hex: 0x0F1118),
            card: Color(hex: 0x1B1F2A),
            cardStroke: Color(hex: 0x2F3547),
            ink: Color(hex: 0xEDEBF3),
            inkSoft: Color(hex: 0x9AA0B4),
            accent: Color(hex: 0xFFB454),
            accentSoft: Color(hex: 0xC98B3E),
            brass: Color(hex: 0xFFD79A),
            done: Color(hex: 0x7FD1A8),
            memo: Color(hex: 0x36301F),
            memoInk: Color(hex: 0xF1E5C6),
            tape: Color(hex: 0x474254),
            shadow: 0.55
        )
    )
}

// MARK: - 환경 주입

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.photoCafe
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
