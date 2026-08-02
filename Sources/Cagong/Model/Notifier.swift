import Foundation
import UserNotifications

/// 로컬 알림을 띄운다.
///
/// **애플 푸시(APNs)는 쓰지 않는다.** 쓰려면 Apple Developer Program 유료 회원과
/// 정식 서명이 필요한데 지금은 ad-hoc 서명이다. 친구 기능이 붙어도 같은 방식으로 간다 —
/// 앱이 켜져 있는 동안 서버를 구독하다가, 친구 이벤트가 오면 여기로 넘겨 띄운다.
/// 앱이 꺼져 있으면 안 오지만, 공부 타이머라 공부 중엔 켜져 있다.
@MainActor
final class Notifier {

    static let shared = Notifier()

    /// 알림 센터를 만질 수 있는 실행 형태인지.
    ///
    /// Xcode에서 `Package.swift`를 열고 ⌘R로 돌리면 SwiftPM이 `.app` 번들이 아니라
    /// 맨 실행파일을 만든다. 그 상태로 `UNUserNotificationCenter.current()`를 건드리면
    /// 번들 정보가 없어 죽는다. `build.sh`로 만든 번들에서만 켠다.
    private let isBundled = Bundle.main.bundleIdentifier != nil

    private var authorized = false
    private var didAsk = false

    private init() {}

    /// 권한을 물어본다. 앱을 켤 때 한 번만.
    func requestAuthorization() {
        guard isBundled, !didAsk else { return }
        didAsk = true

        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                Task { @MainActor in self.authorized = granted }
            }
    }

    /// 내 이벤트를 알림으로 띄운다. 띄울 만한 이벤트가 아니면 아무 일도 안 한다.
    func post(_ event: StudyEvent) {
        guard event.kind.notifiesSelf else { return }
        post(title: event.selfTitle, body: event.selfBody)
    }

    func post(title: String, body: String) {
        guard isBundled, authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // trigger가 nil이면 즉시 띄운다.
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
