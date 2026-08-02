import SwiftUI
import AppKit

/// 화면을 오프스크린으로 렌더링해 PNG로 떨어뜨린다.
/// 데스크톱을 캡처하지 않고 UI를 검수하기 위한 도구다. 앱 번들에는 들어가지 않는다.
///
///   swiftc -parse-as-library -target arm64-apple-macos14.0 -o snapshot \
///       $(find Sources/Cagong -name '*.swift' ! -name 'CagongApp.swift') Tools/Snapshot.swift
///   ./snapshot <출력디렉터리>
@main
@MainActor
struct Snapshot {

    static func main() {
        let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                         ? CommandLine.arguments[1]
                         : FileManager.default.currentDirectoryPath)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // 맨 실행파일에는 앱 번들이 없으므로 소스 트리에서 리소스를 찾게 해준다.
        BundledResources.extraRoots = [URL(fileURLWithPath: "Sources/Cagong/Resources")]
        print("배경 \(PhotoLibrary.shared.scenes.count)장, "
              + "음료 \(Drink.all.filter { DrinkLibrary.shared.image(for: $0) != nil }.count)/\(Drink.all.count)장 찾음")

        // 테마별 타이머 화면
        for theme in Theme.all {
            render(
                name: "timer-\(theme.id.rawValue)",
                fixture: activeFixture(theme: theme.id),
                tab: .study,
                to: outDir
            )
        }

        // 사진 테마의 다른 장면들
        for scene in PhotoLibrary.shared.scenes.dropFirst() {
            render(
                name: "photo-\(scene.id)",
                fixture: activeFixture(theme: .photoCafe, scene: scene.id),
                tab: .study,
                to: outDir
            )
        }

        // 음료 4종 — 컵 층이 제대로 그려지는지
        for drink in Drink.all {
            render(
                name: "drink-\(drink.id.rawValue)",
                fixture: activeFixture(theme: .cafe, drink: drink.id),
                tab: .study,
                to: outDir
            )
        }

        render(name: "setup-cafe", fixture: emptyFixture(theme: .cafe), tab: .study, to: outDir)
        render(name: "monthly-cafe", fixture: activeFixture(theme: .cafe), tab: .monthly, to: outDir)
        render(name: "monthly-photo",
               fixture: activeFixture(theme: .photoCafe, scene: PhotoLibrary.shared.scenes.first?.id),
               tab: .monthly, to: outDir)

        renderSettings(theme: .cafe, to: outDir)
        renderSettings(theme: .photoCafe, to: outDir)

        print("done → \(outDir.path)")
    }

    // MARK: 렌더링

    static func render(name: String, fixture: AppData, tab: RootView.Tab, to dir: URL) {
        let store = StudyStore(fileURL: tempStore())
        store.loadFixture(fixture)

        let view = RootView(initialTab: tab)
            .environmentObject(store)
            .frame(width: 1000, height: 730)

        write(view, name: name, to: dir)
    }

    static func renderSettings(theme: Theme, to dir: URL) {
        let store = StudyStore(fileURL: tempStore())
        store.loadFixture(activeFixture(
            theme: theme.id,
            scene: PhotoLibrary.shared.scenes.first?.id
        ))

        // ScrollView는 오프스크린 렌더러에서 본문을 그리지 않으므로
        // 스크롤 컨테이너 없는 SettingsContent를 직접 그려 검수한다.
        for tab in SettingsTab.allCases {
            let view = SettingsContent(theme: theme, tab: tab)
                .environmentObject(store)
                .frame(width: 470)
                .background(theme.p.card)

            write(view, name: "settings-\(theme.id.rawValue)-\(tab.rawValue)", to: dir)
        }
    }

    static func write<V: View>(_ view: V, name: String, to dir: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            print("✗ \(name)")
            return
        }

        let url = dir.appendingPathComponent("\(name).png")
        try? png.write(to: url)
        print("✓ \(name).png")
    }

    // MARK: 픽스처

    static func tempStore() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cagong-snapshot-\(UUID().uuidString).json")
    }

    /// 진행 중인 하루 + 지난 기록이 있는 상태
    static func activeFixture(
        theme: ThemeID,
        drink: DrinkID = .cafeLatte,
        scene: String? = nil
    ) -> AppData {
        var days: [String: DayRecord] = [:]
        let cal = Calendar.current
        let hours: [Double] = [3.2, 0, 5.1, 1.4, 4.0, 0, 2.6, 6.2, 0, 3.8, 4.4, 1.1, 0, 5.5, 2.0]

        for (offset, h) in hours.enumerated() where h > 0 {
            guard let date = cal.date(byAdding: .day, value: -(offset + 1), to: Date()) else { continue }
            days[DateKey.string(from: date)] = DayRecord(
                seconds: h * 3600,
                todos: [TodoItem(text: "지난 기록", done: true)],
                endedAt: date
            )
        }

        // 오늘은 아직 마무리하지 않은 상태로 둔다.
        days[DateKey.today()] = DayRecord(
            seconds: 5_096,
            todos: [
                TodoItem(text: "자료구조 3단원 정리", done: true),
                TodoItem(text: "알고리즘 문제 5개", done: true),
                // 고정한 루틴 — 압정 표시가 보이는지 확인용
                TodoItem(text: "영어 단어 50개 암기", done: false, pinned: true),
                TodoItem(text: "논문 초안 introduction", done: false)
            ],
            closed: false,
            goalMinutes: 300
        )

        return AppData(
            settings: AppSettings(
                themeID: theme,
                dailyGoalMinutes: 240,
                drinkID: drink,
                photoSceneID: scene
            ),
            days: days
        )
    }

    /// 아직 하루를 시작하지 않은 상태
    static func emptyFixture(theme: ThemeID) -> AppData {
        AppData(settings: AppSettings(themeID: theme, dailyGoalMinutes: 240, drinkID: .matchaLatte))
    }
}
