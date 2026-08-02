import SwiftUI
import Combine
import AppKit

/// 앱 셸. 배경 장면 위에 상단 바와 본문을 얹는다.
struct RootView: View {
    @EnvironmentObject private var store: StudyStore
    @EnvironmentObject private var friendSync: FriendSync
    @ObservedObject private var library = PhotoLibrary.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tab: Tab = .study
    @State private var showSettings = false

    /// 화면을 넘어갈 때 컵이 두 화면 사이를 날아간다.
    @Namespace private var cupSpace
    /// 탭 알약이 미끄러진다.
    @Namespace private var tabSpace

    enum Tab: Hashable { case study, monthly }

    /// - Parameter initialTab: 스냅샷 렌더링에서 특정 탭을 바로 띄우기 위한 진입점.
    init(initialTab: Tab = .study) {
        _tab = State(initialValue: initialTab)
    }

    private var theme: Theme { store.theme }

    var body: some View {
        GeometryReader { geo in
            // 창이 좁아지면 떠 있던 장면 화살표가 카드 위로 올라탄다.
            // 숨기는 대신 상단 바로 옮긴다 — 없애면 장면을 넘길 방법이
            // 단축키밖에 안 남아 발견할 수가 없다.
            let floatingArrows = geo.size.width >= Self.arrowsFloatFrom

            VStack(spacing: 0) {
                topBar(compactArrows: !floatingArrows)

                // 남은 자리에 본문을 담고, 모자라면 스크롤로 받아준다.
                // 이게 있어야 창을 어디까지 줄여도 잘려서 못 쓰는 상태가 안 된다.
                GeometryReader { inner in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        content
                            .padding(.horizontal, floatingArrows ? contentInset : narrowInset)
                            .padding(.bottom, bottomInset)
                            // 자리가 남을 때는 스크롤이 아니라 가운데 정렬이 되게 한다.
                            .frame(
                                minWidth: inner.size.width,
                                minHeight: inner.size.height
                            )
                    }
                }
            }
            .overlay {
                if floatingArrows && showsSceneArrows {
                    sceneArrows
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        // 배경은 ZStack 형제가 아니라 .background로 넣는다.
        //
        // 형제로 두면 배경 사진이 레이아웃에 참여한다. 사진은 화면을 채우려고
        // 제안된 크기를 넘어서 커지는데, 그러면 ZStack도 같이 부풀고 상단 바가
        // 부푼 영역 기준으로 중앙 정렬돼 화면 위로 밀려 올라간다.
        // .background는 콘텐츠 크기에 영향을 주지 않으므로 이 경로가 막힌다.
        .background {
            ThemeBackground(
                theme: theme,
                animate: !reduceMotion,
                photoSceneID: store.settings.photoSceneID
            )
        }
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
        .animation(Motion.screen, value: store.settings.themeID)
        .sheet(isPresented: $showSettings) {
            SettingsView(theme: theme)
                .environmentObject(store)
                .environmentObject(friendSync)
        }
        // 종료 직전 마지막 몇 초를 흘리지 않는다.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            store.flush()
        }
        // 저장은 평소엔 모아뒀다 쓴다(클릭을 붙잡지 않으려고). 다른 앱으로 넘어가는
        // 순간은 그대로 안 돌아올 수도 있는 지점이라 여기서 확실히 쓴다.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            store.flush()
        }
        // 목표를 절반·전부 채운 순간을 알린다.
        // 친구 기능이 붙으면 같은 이벤트가 서버로도 나간다.
        .onReceive(store.events) { event in
            Notifier.shared.post(event)
        }
        .onAppear {
            Notifier.shared.requestAuthorization()
            friendSync.start()
        }
    }

    private let contentInset: CGFloat = 32
    private let narrowInset: CGFloat = 14
    private let bottomInset: CGFloat = 26

    /// 이 폭 아래로는 떠 있는 장면 화살표가 카드를 침범한다.
    ///
    /// 타이머 화면이 가장 넓다(카드 468 + 메모지 268 − 겹침 22 = 714).
    /// 화살표는 양끝에서 60씩(여백 22 + 버튼 38) 차지하므로 714 + 120 = 834가
    /// 부딪히기 시작하는 지점이다. 조금 여유를 둔다.
    private static let arrowsFloatFrom: CGFloat = 860

    private var showsSceneArrows: Bool {
        theme.scene.isPhoto && library.scenes.count > 1
    }

    // MARK: 상단 바

    /// 상단 바.
    ///
    /// 한 줄 HStack으로 두면 창을 좁혔을 때 스페이서가 먼저 0이 되고 오른쪽 끝의
    /// 톱니가 밀려 나가 사라진다. 그래서 가운데 탭과 양끝 요소를 겹쳐 배치한다 —
    /// 탭은 항상 화면 가운데, 톱니는 항상 오른쪽 끝에 고정된다.
    ///
    /// - Parameter compactArrows: 창이 좁아 장면 화살표가 여기로 들어와야 하는지.
    private func topBar(compactArrows: Bool) -> some View {
        ZStack {
            tabSwitch

            HStack(spacing: 12) {
                leadingGroup
                Spacer(minLength: 8)

                HStack(spacing: 7) {
                    if compactArrows && showsSceneArrows {
                        sceneArrow("chevron.left", offset: -1, help: "이전 장면 (⌘←)", side: 30)
                        sceneArrow("chevron.right", offset: 1, help: "다음 장면 (⌘→)", side: 30)
                    }
                    settingsButton
                }
            }
        }
        // 왼쪽은 신호등 버튼 자리를 비워둔다.
        .padding(.leading, 84)
        .padding(.trailing, 22)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    /// 창이 좁아지면 브랜드 글자를 접는다.
    /// 접히는 순서를 정해두지 않으면 톱니가 밀려 나간다.
    private var leadingGroup: some View {
        ViewThatFits(in: .horizontal) {
            brand
            Color.clear.frame(width: 0, height: 0)
        }
    }

    private var brand: some View {
        Text("CAGONG")
            .font(Typo.label(12))
            .tracking(3.4)
            .fixedSize()
            .foregroundStyle(theme.scene.isPhoto ? theme.p.card : theme.p.inkSoft.opacity(0.9))
    }

    private var tabSwitch: some View {
        HStack(spacing: 3) {
            tabButton(.study, label: store.isDayOpen ? "공부" : "시작")
            tabButton(.monthly, label: "먼슬리")
        }
        .padding(3)
        .glass(Capsule())
    }



    private func tabButton(_ target: Tab, label: String) -> some View {
        let selected = tab == target

        return Button {
            withAnimation(Motion.screen) { tab = target }
        } label: {
            Text(label)
                .font(Typo.bodyStrong(13))
                .foregroundStyle(
                    selected
                    ? (theme.isDark ? Color(hex: 0x14161E) : .white)
                    : theme.p.inkSoft
                )
                .padding(.horizontal, 17)
                .padding(.vertical, 7)
                .background {
                    if selected {
                        Capsule()
                            .fill(theme.p.accent)
                            .matchedGeometryEffect(id: "tabPill", in: tabSpace)
                    }
                }
        }
        .buttonStyle(PressableStyle())
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.scene.isPhoto ? theme.p.ink : theme.p.inkSoft)
                .frame(width: 32, height: 32)
                .glass(Circle())
        }
        .buttonStyle(PressableStyle())
        .keyboardShortcut(",", modifiers: .command)
        .help("설정 (⌘,)")
    }

    // MARK: 사진 장면 전환

    private var sceneArrows: some View {
        HStack {
            sceneArrow("chevron.left", offset: -1, help: "이전 장면 (⌘←)")
            Spacer()
            sceneArrow("chevron.right", offset: 1, help: "다음 장면 (⌘→)")
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sceneArrow(
        _ icon: String,
        offset: Int,
        help: String,
        side: CGFloat = 38
    ) -> some View {
        Button {
            withAnimation(Motion.screen) { store.stepPhotoScene(offset) }
        } label: {
            Image(systemName: icon)
                .font(.system(size: side > 34 ? 13 : 11, weight: .bold))
                .foregroundStyle(theme.p.ink)
                .frame(width: side, height: side)
                .glass(Circle())
        }
        .buttonStyle(PressableStyle())
        .keyboardShortcut(offset < 0 ? .leftArrow : .rightArrow, modifiers: .command)
        .help(help)
    }

    // MARK: 본문

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .study:
            if store.isDayOpen {
                TimerView(theme: theme, namespace: cupSpace)
                    .transition(screenTransition)
            } else {
                TodoSetupView(theme: theme)
                    .transition(screenTransition)
            }
        case .monthly:
            MonthlyView(theme: theme, namespace: cupSpace)
                .transition(screenTransition)
        }
    }

    private var screenTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 16)),
            removal: .opacity.combined(with: .offset(y: -12))
        )
    }
}
