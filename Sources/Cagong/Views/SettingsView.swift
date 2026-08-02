import SwiftUI
import AppKit

/// 설정 시트. 제목 줄 + 스크롤되는 본문.
///
/// 본문은 `SettingsContent`로 떼어 두었다. 스크롤 컨테이너 없이도 렌더링할 수 있어서
/// 오프스크린 스냅샷으로 검수가 되고, 섹션이 늘어나면 스크롤이 자동으로 받아준다.
/// 설정 갈래. 항목이 늘어나면 여기에 한 줄 추가하면 된다.
///
/// 하루 목표는 여기 없다. 목표는 날마다 다른데(시험 기간과 주말이 같을 리 없다)
/// 설정에 하나로 박아두면 매번 설정을 열어 고쳐야 한다.
/// 그래서 타이머 화면의 목표 문구를 눌러 그날치를 바로 정하도록 옮겼다.
enum SettingsTab: String, CaseIterable, Identifiable {
    case drink
    case theme
    case friends

    var id: String { rawValue }

    var label: String {
        switch self {
        case .drink: return "음료"
        case .theme: return "테마"
        case .friends: return "친구"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    let theme: Theme

    @State private var tab: SettingsTab = .drink
    @Namespace private var tabSpace

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            tabBar

            ScrollView(.vertical, showsIndicators: false) {
                SettingsContent(theme: theme, tab: tab)
            }
        }
        .frame(width: 470, height: 640)
        .background(theme.p.card)
    }

    // MARK: 탭

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(SettingsTab.allCases) { candidate in
                tabButton(candidate)
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.p.ink.opacity(theme.isDark ? 0.2 : 0.055)))
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func tabButton(_ candidate: SettingsTab) -> some View {
        let selected = candidate == tab

        return Button {
            withAnimation(Motion.screen) { tab = candidate }
        } label: {
            Text(candidate.label)
                .font(Typo.bodyStrong(13))
                .foregroundStyle(
                    selected
                    ? (theme.isDark ? Color(hex: 0x14161E) : .white)
                    : theme.p.inkSoft
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if selected {
                        Capsule()
                            .fill(theme.p.accent)
                            .matchedGeometryEffect(id: "settingsTabPill", in: tabSpace)
                    }
                }
        }
        .buttonStyle(PressableStyle())
    }

    private var titleBar: some View {
        HStack {
            Text("설정")
                .font(Typo.title(17))
                .foregroundStyle(theme.p.ink)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.p.inkSoft)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(theme.p.ink.opacity(0.06)))
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.p.cardStroke).frame(height: 1)
        }
    }
}

/// 설정 본문.
struct SettingsContent: View {
    @EnvironmentObject private var store: StudyStore
    @ObservedObject private var library = PhotoLibrary.shared
    let theme: Theme
    let tab: SettingsTab

    /// 마우스가 올라간 사진 장면. 여기에만 지우기 X가 뜬다.
    @State private var hoveredScene: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            switch tab {
            case .drink:
                drinkSection

            case .theme:
                themeSection
                if store.settings.themeID == .photoCafe {
                    photoSection
                }

            case .friends:
                FriendsSection(theme: theme)
            }

            // MARK: 확장 지점 — 사운드(BGM)
            // SettingsTab에 case를 하나 추가하고 여기에 분기를 붙이면 된다.
            //   1. AppSettings에 필드 추가 (예: bgmVolume, bgmTrack)
            //      → 열거형은 원시 문자열로 읽으므로 기존 저장 파일이 깨지지 않는다.
            //   2. StudyStore에 setter 추가 (setTheme/setDailyGoal과 같은 모양)
            //   3. sectionHeader("사운드", ...) + 컨트롤 배치
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 음료

    private var drinkSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("음료", note: "컵에 담기는 음료")
            DrinkPicker(
                selected: store.settings.drinkID,
                theme: theme,
                onSelect: { store.setDrink($0) }
            )
        }
    }

    // MARK: 사진 장면

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("사진 장면", note: "타이머 화면에서 ← → 로도 넘길 수 있어요")

            VStack(alignment: .leading, spacing: 12) {
                // 스크롤 대신 격자로 둔다. 사진이 늘어나면 줄로 넘어간다.
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                    spacing: 10
                ) {
                    ForEach(library.scenes) { scene in
                        sceneThumb(scene)
                    }
                }

                HStack(spacing: 8) {
                    Button("사진 추가") { addPhotos() }
                        .buttonStyle(GhostButtonStyle(theme: theme))
                    Button("폴더 열기") {
                        NSWorkspace.shared.open(library.userFolder)
                    }
                    .buttonStyle(GhostButtonStyle(theme: theme))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.p.ink.opacity(theme.isDark ? 0.10 : 0.035))
            )
        }
    }

    /// 장면 하나.
    ///
    /// 지우기 버튼은 선택 영역 **안이 아니라 위에** 겹쳐 둔다. Button의 label 안에
    /// 또 Button을 넣으면 macOS에서 안쪽 버튼이 눌리지 않는다. 그래서 선택은
    /// `onTapGesture`로 받고, X만 진짜 Button으로 남긴다.
    private func sceneThumb(_ scene: PhotoScene) -> some View {
        let isOn = (store.settings.photoSceneID ?? library.scenes.first?.id) == scene.id
        let hovering = hoveredScene == scene.id

        return VStack(spacing: 6) {
            ZStack {
                if let img = library.image(for: scene) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    theme.p.inkSoft.opacity(0.2)
                }
            }
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isOn ? theme.p.accent : theme.p.cardStroke.opacity(0.6),
                        lineWidth: isOn ? 2 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                // 기본 4장은 지울 수 없다. 직접 넣은 사진에만 X가 뜬다.
                if !scene.bundled, hovering {
                    deleteBadge(scene)
                }
            }

            Text(scene.name)
                .font(Typo.body(11))
                .foregroundStyle(isOn ? theme.p.ink : theme.p.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(Motion.button, value: hovering)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Motion.screen) { store.setPhotoScene(scene.id) }
        }
        .onHover { inside in
            if inside { hoveredScene = scene.id }
            else if hoveredScene == scene.id { hoveredScene = nil }
        }
    }

    private func deleteBadge(_ scene: PhotoScene) -> some View {
        Button {
            deleteScene(scene)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(.black.opacity(0.62)))
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.8))
        }
        .buttonStyle(PressableStyle())
        .padding(4)
        .help("사진 지우기 — 휴지통으로 갑니다")
        .transition(.opacity.combined(with: .scale))
    }

    /// 지운 장면이 지금 쓰던 것이면 첫 장면으로 되돌린다.
    private func deleteScene(_ scene: PhotoScene) {
        let wasSelected = (store.settings.photoSceneID ?? library.scenes.first?.id) == scene.id

        withAnimation(Motion.card) {
            guard library.remove(scene) else { return }
            if wasSelected {
                store.setPhotoScene(library.scenes.first?.id)
            }
        }
    }

    /// 고른 사진을 사용자 폴더로 복사한다. 원본은 건드리지 않는다.
    private func addPhotos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.message = "배경으로 쓸 사진을 고르세요"
        guard panel.runModal() == .OK else { return }

        var lastAdded: String?
        for source in panel.urls {
            let destination = library.userFolder.appendingPathComponent(source.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                lastAdded = destination.deletingPathExtension().lastPathComponent
            } catch {
                continue
            }
        }

        library.reload()
        if let lastAdded { store.setPhotoScene(lastAdded) }
    }

    // MARK: 테마

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("테마", note: "고르면 바로 적용됩니다")
            VStack(spacing: 7) {
                ForEach(Theme.all) { candidate in
                    themeRow(candidate)
                }
            }
        }
    }

    private func themeRow(_ candidate: Theme) -> some View {
        let selected = candidate.id == store.settings.themeID

        return Button {
            withAnimation(Motion.screen) { store.setTheme(candidate.id) }
        } label: {
            HStack(spacing: 13) {
                // 실제 배경을 축소해 보여준다. 설명보다 이게 빠르다.
                ThemePreview(theme: candidate, width: 74, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(theme.p.cardStroke, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(Typo.bodyStrong(13.5))
                        .foregroundStyle(theme.p.ink)
                    Text(candidate.blurb)
                        .font(Typo.body(11.5))
                        .foregroundStyle(theme.p.inkSoft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                InkCheckbox(
                    done: selected,
                    tint: theme.p.accent,
                    boxColor: theme.p.inkSoft,
                    size: 19
                )
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.p.accent.opacity(selected ? 0.07 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                selected ? theme.p.accent.opacity(0.55) : theme.p.cardStroke.opacity(0.6),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PressableStyle(scale: 0.985))
    }

    // MARK: 공통

    /// 섹션 제목은 한글이므로 Eyebrow(대문자 + 넓은 자간, 라틴 전용)를 쓰지 않는다.
    private func sectionHeader(_ title: String, note: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(Typo.bodyStrong(13))
                .foregroundStyle(theme.p.accentSoft)
            if let note {
                Text(note)
                    .font(Typo.body(11))
                    .foregroundStyle(theme.p.inkSoft.opacity(0.8))
            }
        }
        .padding(.bottom, 9)
    }
}
