import SwiftUI
import AppKit

enum DrinkID: String, Codable, CaseIterable, Identifiable {
    case espresso
    case matchaLatte
    case lemonade
    case americano
    case cafeLatte
    case chocoFrappuccino

    var id: String { rawValue }
}

/// 컵에 담기는 음료.
///
/// 배경만 지운 실제 사진을 아무 보정 없이 그대로 쓴다. 사진은
/// `Tools/NormalizeDrinks`로 640×640 캔버스에 하단 정렬돼 있어서
/// 어떤 음료를 골라도 잔이 같은 자리에 놓인다.
struct Drink: Identifiable {
    let id: DrinkID
    /// 메뉴판에 적히는 이름
    let name: String
    /// 고를 때 도움말로 보이는 한 줄
    let blurb: String
    /// `Resources/Drinks` 안의 파일 이름 (확장자 제외)
    let asset: String
    /// 뜨거운 음료만 김이 오른다.
    let hot: Bool

    static func by(_ id: DrinkID) -> Drink {
        all.first { $0.id == id } ?? all[0]
    }

    static let all: [Drink] = [
        Drink(
            id: .espresso,
            name: "Espresso",
            blurb: "잔 받침까지 갖춘 한 잔",
            asset: "espresso",
            hot: true
        ),
        Drink(
            id: .matchaLatte,
            name: "Matcha Latte",
            blurb: "우유 위로 초록이 내려앉는다",
            asset: "matcha-latte",
            hot: false
        ),
        Drink(
            id: .lemonade,
            name: "Lemonade",
            blurb: "레몬 슬라이스와 민트",
            asset: "lemonade",
            hot: false
        ),
        Drink(
            id: .americano,
            name: "Americano",
            blurb: "진하고 검다. 오래 앉을 때",
            asset: "americano",
            hot: true
        ),
        Drink(
            id: .cafeLatte,
            name: "Cafe Latte",
            blurb: "거품에 그린 잎",
            asset: "cafe-latte",
            hot: true
        ),
        Drink(
            id: .chocoFrappuccino,
            name: "Chocolate Frappuccino",
            blurb: "생크림 올린 차가운 초콜릿",
            asset: "choco-frappuccino",
            hot: false
        )
    ]
}

// MARK: - 음료 사진 보관소

/// 누끼 딴 음료 사진을 읽어 캐시한다. 보정은 하지 않는다.
@MainActor
final class DrinkLibrary: ObservableObject {

    static let shared = DrinkLibrary()

    private var cache: [String: NSImage] = [:]

    func image(for drink: Drink) -> NSImage? {
        if let hit = cache[drink.asset] { return hit }

        for folder in BundledResources.folders(named: "Drinks") {
            let url = folder.appendingPathComponent("\(drink.asset).png")
            if let image = NSImage(contentsOf: url) {
                cache[drink.asset] = image
                return image
            }
        }
        return nil
    }
}
