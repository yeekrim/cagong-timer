import SwiftUI

/// 하루를 시작하기 전 화면.
///
/// 할 일을 적어두면 타이머 옆 메모지로 넘어간다. 비워두고 바로 시작해도 된다 —
/// 시작 버튼은 항상 눌린다.
struct TodoSetupView: View {
    @EnvironmentObject private var store: StudyStore
    let theme: Theme

    @State private var drafts: [TodoItem] = []
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            card
            Spacer(minLength: 12)
        }
        .onAppear {
            loadRoutines()
            inputFocused = true
        }
    }

    /// 고정해둔 루틴을 미리 깔아준다.
    ///
    /// 매일 똑같이 적게 하지 않으려고 있는 기능이므로, 시작 화면에 **이미 올라온 채로**
    /// 보여야 한다. 오늘 필요 없으면 그 자리에서 지우면 그만이다.
    private func loadRoutines() {
        guard drafts.isEmpty else { return }
        drafts = store.routineDrafts(for: store.measuringKey)
    }

    /// 제목·안내 문구까지 한 판에 올린다.
    ///
    /// 입력칸에만 유리를 씌우면 제목과 안내 문구가 사진 위에 맨 글자로 남아
    /// 장면에 따라 아예 안 읽힌다. 타이머 화면처럼 한 덩어리로 묶는다.
    private var card: some View {
        VStack(spacing: 0) {
            heading

            pad
                .padding(.top, 22)

            drinkChoice
                .padding(.top, 20)

            actions
                .padding(.top, 22)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 28)
        // 좁은 창에서는 줄어든다. 음료 고르기는 유연 격자라 따라 줄어든다.
        .frame(maxWidth: 520)
        .glass(
            RoundedRectangle(cornerRadius: 22, style: .continuous),
            tint: theme.p.card,
            tintOpacity: 0.22
        )
    }

    // MARK: 조각

    private var heading: some View {
        VStack(spacing: 10) {
            Eyebrow(text: "New Day", theme: theme, color: theme.p.accentSoft)

            Text("오늘 뭐부터 할까요?")
                .font(Typo.title(30))
                .foregroundStyle(theme.p.ink)

            Text("적어두면 타이머 옆에 붙여둘게요.")
                .font(Typo.body(14))
                .foregroundStyle(theme.p.inkSoft)
        }
    }

    private var pad: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 입력
            HStack(spacing: 10) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.p.accentSoft)

                TextField("할 일을 적고 Enter", text: $input)
                    .textFieldStyle(.plain)
                    .font(Typo.body(15))
                    .foregroundStyle(theme.p.ink)
                    .focused($inputFocused)
                    .onSubmit(add)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            if !drafts.isEmpty {
                Divider().overlay(theme.p.cardStroke)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(drafts) { item in
                        draftRow(item)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        // 바깥 판이 이미 유리다. 여기까지 유리로 겹치면 탁해지므로
        // 안쪽으로 살짝 파인 입력면으로 둔다.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.p.ink.opacity(theme.isDark ? 0.16 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.p.ink.opacity(0.09), lineWidth: 1)
                )
        )
    }

    private func draftRow(_ item: TodoItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(theme.p.inkSoft.opacity(0.5), lineWidth: 1.4)
                .frame(width: 17, height: 17)

            Text(item.text)
                .font(Typo.body(15))
                .foregroundStyle(theme.p.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 루틴으로 딸려온 항목은 왜 여기 있는지 알 수 있어야 한다.
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.p.accentSoft.opacity(0.8))
                    .help("루틴 — 매일 따라옵니다")
            }

            Button {
                withAnimation(Motion.paper) {
                    drafts.removeAll { $0.id == item.id }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.p.inkSoft.opacity(0.6))
            }
            .buttonStyle(PressableStyle())
            .help("지우기")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// 레퍼런스처럼 시작 전에 음료를 고른다.
    private var drinkChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("오늘 뭐 마실까요?")
                .font(Typo.bodyStrong(13))
                .foregroundStyle(theme.p.accentSoft)

            DrinkPicker(
                selected: store.settings.drinkID,
                theme: theme,
                onSelect: { store.setDrink($0) }
            )
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button("공부 시작") {
                withAnimation(Motion.screen) {
                    store.beginDay(todos: drafts)
                    store.start()
                }
            }
            .buttonStyle(PrimaryButtonStyle(theme: theme, wide: true))

            Text(drafts.isEmpty ? "비워두고 시작해도 괜찮아요." : "\(drafts.count)개를 메모지에 붙여둘게요.")
                .font(Typo.body(12.5))
                .foregroundStyle(theme.p.inkSoft.opacity(0.85))
                .contentTransition(.opacity)
                .animation(Motion.button, value: drafts.count)
        }
    }

    private func add() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(Motion.paper) {
            drafts.append(TodoItem(text: text))
        }
        input = ""
        inputFocused = true
    }
}
