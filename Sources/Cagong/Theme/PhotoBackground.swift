import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - 장면

struct PhotoScene: Identifiable, Hashable {
    /// 확장자를 뗀 파일 이름
    let id: String
    let name: String
    let url: URL
    /// 앱에 포함된 사진인지, 사용자가 넣은 사진인지
    let bundled: Bool
}

// MARK: - 사진 보관소

/// 배경 사진을 찾아 읽고, 읽어둔 결과를 캐시한다.
///
/// 사진은 두 곳에서 온다.
///   1. 앱 번들 (`Resources/Backgrounds`) — 포함해 배포하는 기본 장면
///   2. `~/Library/Application Support/Cagong/Backgrounds` — 사용자가 직접 넣는 사진
///
/// 두 번째 폴더에 JPEG/PNG를 넣고 앱을 다시 켜면 장면 목록에 바로 나타난다.
@MainActor
final class PhotoLibrary: ObservableObject {

    static let shared = PhotoLibrary()

    @Published private(set) var scenes: [PhotoScene] = []

    private var cache: [String: NSImage] = [:]
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// 번들 사진이 보이는 순서. 첫 항목이 기본 장면이 된다.
    ///
    /// 딕셔너리 키 순서는 보장되지 않으므로 순서는 반드시 배열로 따로 둔다.
    /// 여기를 `bundledNames.keys`로 두면 실행마다 기본 장면이 바뀐다.
    private static let bundledOrder = ["paris-summer", "montmartre-cafe", "tokyo-dusk", "seine-night"]

    /// 번들 사진의 한글 이름. 사용자 사진은 파일 이름을 그대로 쓴다.
    private static let bundledNames: [String: String] = [
        "paris-summer": "파리의 여름",
        "montmartre-cafe": "몽마르트 카페",
        "tokyo-dusk": "도쿄 노을",
        "seine-night": "센강의 밤"
    ]

    private static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff"]

    init() { reload() }

    // MARK: 폴더

    /// 사용자가 사진을 넣는 폴더. 없으면 만든다.
    var userFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support
            .appendingPathComponent("Cagong", isDirectory: true)
            .appendingPathComponent("Backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var bundledFolders: [URL] { BundledResources.folders(named: "Backgrounds") }

    // MARK: 목록

    func reload() {
        var found: [PhotoScene] = []
        var seen = Set<String>()

        for folder in bundledFolders {
            for url in imageFiles(in: folder) {
                let id = url.deletingPathExtension().lastPathComponent
                guard !seen.contains(id) else { continue }
                seen.insert(id)
                found.append(PhotoScene(
                    id: id,
                    name: Self.bundledNames[id] ?? id,
                    url: url,
                    bundled: true
                ))
            }
        }

        for url in imageFiles(in: userFolder) {
            let id = url.deletingPathExtension().lastPathComponent
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            found.append(PhotoScene(id: id, name: id, url: url, bundled: false))
        }

        // 번들 사진은 정해진 순서로, 사용자 사진은 이름순으로
        scenes = found.sorted { a, b in
            switch (a.bundled, b.bundled) {
            case (true, false): return true
            case (false, true): return false
            case (true, true):
                let ia = Self.bundledOrder.firstIndex(of: a.id) ?? Int.max
                let ib = Self.bundledOrder.firstIndex(of: b.id) ?? Int.max
                return ia == ib ? a.id < b.id : ia < ib
            case (false, false):
                return a.id.localizedStandardCompare(b.id) == .orderedAscending
            }
        }
    }

    private func imageFiles(in folder: URL) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return items
            .filter { Self.extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 사용자가 넣은 사진을 지운다.
    ///
    /// 영구 삭제가 아니라 휴지통으로 보낸다 — 폴더에 직접 넣은 사진이면
    /// 그게 유일한 사본일 수 있다. 번들 사진은 지울 수 없다.
    @discardableResult
    func remove(_ scene: PhotoScene) -> Bool {
        guard !scene.bundled else { return false }

        do {
            try FileManager.default.trashItem(at: scene.url, resultingItemURL: nil)
        } catch {
            return false
        }

        cache[scene.id] = nil
        reload()
        return true
    }

    func scene(id: String?) -> PhotoScene? {
        if let id, let match = scenes.first(where: { $0.id == id }) { return match }
        return scenes.first
    }

    /// 목록에서 다음/이전 장면
    func neighbour(of id: String?, offset: Int) -> PhotoScene? {
        guard !scenes.isEmpty else { return nil }
        let current = scenes.firstIndex(where: { $0.id == id }) ?? 0
        let next = (current + offset + scenes.count) % scenes.count
        return scenes[next]
    }

    // MARK: 이미지

    /// 배경에 쓸 이미지. 한 번 만들면 캐시한다.
    func image(for scene: PhotoScene) -> NSImage? {
        if let hit = cache[scene.id] { return hit }
        guard let made = prepare(scene.url) else { return nil }
        cache[scene.id] = made
        return made
    }

    /// 사진을 거의 그대로 쓴다.
    ///
    /// 카페 사진은 창밖은 밝고 실내는 어두워서, 손대지 않으면 실내가 통째로
    /// 검게 죽는다. 그림자만 살짝 들어올려 그 부분이 보이게 한다.
    /// 채도·대비는 건드리지 않는다 — 사진 그대로의 색을 남긴다.
    private func prepare(_ url: URL) -> NSImage? {
        guard let source = CIImage(contentsOf: url) else { return nil }

        let lift = CIFilter.highlightShadowAdjust()
        lift.inputImage = source
        lift.radius = 14
        lift.shadowAmount = 0.45
        lift.highlightAmount = 0.9

        guard
            let output = lift.outputImage?.cropped(to: source.extent),
            let cg = ciContext.createCGImage(output, from: output.extent)
        else { return nil }

        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}

// MARK: - 사진 배경

/// 사진을 배경으로 깐다.
///
/// 사진 밝기는 장면마다 크게 다르다(심야 카페 vs 초록 중정). 어느 사진에서도
/// 흰 카드와 글자가 읽히도록 위에 균일한 스크림을 덮는다.
struct PhotoBackgroundScene: View {
    let scene: PhotoScene?
    let theme: Theme
    @ObservedObject private var library = PhotoLibrary.shared

    var body: some View {
        ZStack {
            theme.p.backdrop

            if let scene, let image = library.image(for: scene) {
                // GeometryReader는 제안된 크기를 그대로 받아들이고 더 커지지 않는다.
                // 넘치는 부분은 clipped()로 잘라낸다. Image에 .fill만 걸면
                // 프레임을 넘어서 커져 위쪽 콘텐츠를 밀어낸다.
                GeometryReader { geo in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .allowsHitTesting(false)
            } else {
                // 사진을 못 읽었을 때도 화면이 비지 않게 한다.
                LinearGradient(
                    colors: [Color(hex: 0x2A2622), Color(hex: 0x4A423A)],
                    startPoint: .top, endPoint: .bottom
                )
            }

            // 밝기를 살짝만 눌러 고르게 만든다. 세게 덮으면 사진이 안 보인다.
            Color.black.opacity(0.08)

            // 가장자리 비네트 — 시선이 가운데 카드로 모인다
            RadialGradient(
                colors: [.clear, .black.opacity(0.26)],
                center: .center,
                startRadius: 300,
                endRadius: 900
            )
        }
    }
}
