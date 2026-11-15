import SwiftUI
import AppKit

/// Xcode에서 `Package.swift`를 열고 ⌘R로 실행하면 SwiftPM은 `.app` 번들이 아니라
/// 맨 실행파일을 만든다. Info.plist가 없으면 macOS가 이걸 UI 앱으로 보지 않아서
/// 창도 Dock 아이콘도 뜨지 않는다.
///
/// 실행 직후 activation policy를 `.regular`로 올려 UI 앱으로 승격시킨다.
/// `build.sh`로 만든 정식 번들에서는 이미 `.regular`이므로 아무 영향이 없다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let notepad = StudyNotepad()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do {
            try notepad.save()
            return .terminateNow
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "메모를 저장하지 못했습니다"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "확인")
            alert.runModal()
            return .terminateCancel
        }
    }

    /// 창을 닫으면 앱도 끝낸다. 창이 하나뿐인 앱이라 트레이에 남을 이유가 없다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct CagongApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: StudyStore
    /// 친구 동기화. store 하나에 묶여 앱 수명 내내 산다.
    @StateObject private var friendSync: FriendSync

    init() {
        let store = StudyStore()
        _store = StateObject(wrappedValue: store)
        _friendSync = StateObject(wrappedValue: FriendSync(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(appDelegate.notepad)
                .environmentObject(friendSync)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 730)
        .commands {
            // 문서 앱이 아니므로 새 창/새 항목 메뉴는 없앤다.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
