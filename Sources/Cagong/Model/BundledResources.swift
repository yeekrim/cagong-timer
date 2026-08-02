import Foundation

/// 번들에 들어 있는 리소스 폴더를 찾는다.
///
/// 실행 형태마다 위치가 다르다.
///   - `build.sh`로 만든 .app  → `Bundle.main.resourceURL`
///   - `swift build` / Xcode   → `Bundle.module.resourceURL` (SwiftPM이 만든 리소스 번들)
///   - 스냅샷·검증 도구        → 번들이 없으므로 `extraRoots`로 소스 트리를 직접 가리킨다
///
/// 세 경로를 모두 후보로 넘겨주고, 실제로 존재하는 것만 읽는 쪽에서 쓴다.
enum BundledResources {

    /// 도구에서 지정하는 추가 리소스 루트.
    /// `PhotoLibrary.shared` 같은 싱글턴을 처음 건드리기 전에 설정해야 한다.
    static var extraRoots: [URL] = []

    static func folders(named name: String) -> [URL] {
        var urls: [URL] = []

        if let resources = Bundle.main.resourceURL {
            urls.append(resources.appendingPathComponent(name, isDirectory: true))
        }

        #if SWIFT_PACKAGE
        if let moduleResources = Bundle.module.resourceURL {
            urls.append(moduleResources.appendingPathComponent(name, isDirectory: true))
        }
        #endif

        urls.append(contentsOf: extraRoots.map {
            $0.appendingPathComponent(name, isDirectory: true)
        })

        return urls
    }
}
