import SwiftUI

/// 테이프로 붙인 메모지.
///
/// 총 시간 옆에 붙어서 하루 내내 그대로 있는다. 체크는 누르는 즉시 저장되고,
/// "오늘 공부 끝"을 누를 때까지 앱을 껐다 켜도 지워지지 않는다.
struct MemoSlip: View {
    let todos: [TodoItem]
    let theme: Theme
    /// 체크 토글
    let onToggle: (UUID) -> Void
    /// 항목 추가. nil이면 추가 칸을 숨긴다.
    var onAdd: ((String) -> Void)? = nil
    var onRemove: ((UUID) -> Void)? = nil
    /// 루틴 고정 토글. nil이면 압정을 숨긴다.
    var onPin: ((UUID) -> Void)? = nil

    @State private var draft = ""
    @State private var hovered: UUID? = nil
    @FocusState private var addFocused: Bool

    private var doneCount: Int { todos.filter(\.done).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .overlay(theme.p.memoInk.opacity(0.18))
                .padding(.horizontal, 18)

            if todos.isEmpty {
                emptyState
            } else {
                list
            }

            if let onAdd {
                addRow(onAdd)
            }
        }
        .frame(width: 268)
        .background(paper)
        .overlay(alignment: .top) { tape }
        .rotationEffect(.degrees(-1.4))
        .shadow(color: .black.opacity(theme.p.shadow * 0.9), radius: 16, x: 2, y: 10)
    }

    // MARK: 조각

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("TODO")
                .font(Typo.bodyStrong(14))
                .foregroundStyle(theme.p.memoInk)
            Spacer()
            if !todos.isEmpty {
                Text("\(doneCount)/\(todos.count)")
                    .font(Typo.stamp(13))
                    .foregroundStyle(theme.p.memoInk.opacity(0.55))
                    .contentTransition(.numericText())
                    .animation(Motion.digit, value: doneCount)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        Text("비워둬도 괜찮아요.\n생각나면 아래에 적으세요.")
            .font(Typo.body(13))
            .lineSpacing(4)
            .foregroundStyle(theme.p.memoInk.opacity(0.5))
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(todos) { item in
                row(item)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func row(_ item: TodoItem) -> some View {
        // 마우스를 올리면 압정과 X가 나오고, 평소엔 고정된 항목에만 압정이 남는다.
        let showsActions = hovered == item.id && (onRemove != nil || onPin != nil)
        let reserved = showsActions ? Self.actionSlot * 2 : (item.pinned ? Self.badgeSlot : 0)

        return HStack(alignment: .top, spacing: 10) {
            InkCheckbox(
                done: item.done,
                tint: theme.p.done,
                boxColor: theme.p.memoInk
            )
            .padding(.top, 1)

            Text(item.text)
                .font(Typo.body(14))
                .lineSpacing(3)
                .strikethrough(item.done, color: theme.p.memoInk.opacity(0.5))
                .foregroundStyle(theme.p.memoInk.opacity(item.done ? 0.45 : 0.95))
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(Motion.ink, value: item.done)
                // 버튼이 뜰 자리를 글자를 흐리게 지워서 비운다.
                // 폭을 줄이는 게 아니라 마스크로 가리는 것이라 줄바꿈이 생기지 않는다.
                .mask(trailingFade(reserved: reserved))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.p.memoInk.opacity(hovered == item.id ? 0.05 : 0))
        )
        // 버튼은 줄 안이 아니라 위에 띄운다. HStack에 넣으면 글자 폭을 빼앗아
        // 줄바꿈이 생기고, 그만큼 줄 높이가 변해 목록이 위아래로 출렁인다.
        .overlay(alignment: .trailing) {
            if showsActions {
                HStack(spacing: 0) {
                    if let onPin { pinButton(item, action: onPin) }
                    if let onRemove { deleteButton(item, action: onRemove) }
                }
                .transition(.opacity)
            } else if item.pinned {
                pinBadge
            }
        }
        .animation(Motion.button, value: showsActions)
        .contentShape(Rectangle())
        .onTapGesture { onToggle(item.id) }
        .onHover { inside in
            hovered = inside ? item.id : (hovered == item.id ? nil : hovered)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            "\(item.text), \(item.done ? "완료" : "미완료")\(item.pinned ? ", 루틴" : "")"
        )
    }

    /// 압정. 켜면 다음 날에도 따라온다.
    private func pinButton(_ item: TodoItem, action: @escaping (UUID) -> Void) -> some View {
        Button {
            withAnimation(Motion.paper) { action(item.id) }
        } label: {
            Image(systemName: item.pinned ? "pin.fill" : "pin")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.p.memoInk.opacity(item.pinned ? 0.75 : 0.42))
                .rotationEffect(.degrees(item.pinned ? 0 : -28))
                .frame(width: Self.actionSlot, height: Self.actionSlot)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(item.pinned ? "루틴 해제 — 내일부터 안 따라옵니다" : "루틴으로 고정 — 매일 따라옵니다")
    }

    private func deleteButton(_ item: TodoItem, action: @escaping (UUID) -> Void) -> some View {
        Button {
            withAnimation(Motion.paper) { action(item.id) }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.p.memoInk.opacity(0.5))
                .frame(width: Self.actionSlot, height: Self.actionSlot)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help("항목 지우기")
    }

    /// 마우스를 안 올려도 루틴이라는 건 보여야 한다.
    private var pinBadge: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 8.5))
            .foregroundStyle(theme.p.memoInk.opacity(0.35))
            .frame(width: Self.badgeSlot, height: Self.badgeSlot)
            .allowsHitTesting(false)
    }

    /// 버튼 하나가 차지하는 정사각 자리. 버튼은 이 안의 한가운데에 놓인다.
    private static let actionSlot: CGFloat = 28
    /// 압정 표시만 있을 때의 자리
    private static let badgeSlot: CGFloat = 18

    /// 오른쪽 끝으로 갈수록 사라지는 마스크.
    ///
    /// 버튼 자리보다 넉넉하게 흐려야 글자가 버튼 밑에서 잘린 것처럼 보이지 않는다.
    private func trailingFade(reserved: CGFloat) -> some View {
        GeometryReader { geo in
            let fade: CGFloat = reserved > 0 ? reserved + 16 : 0
            let solid = geo.size.width > 0
                ? max(0, (geo.size.width - fade) / geo.size.width)
                : 1

            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: solid),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private func addRow(_ add: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.p.memoInk.opacity(0.45))

            TextField("할 일 추가", text: $draft)
                .textFieldStyle(.plain)
                .font(Typo.body(13))
                .foregroundStyle(theme.p.memoInk)
                .focused($addFocused)
                .onSubmit(submit)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 22)
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let onAdd else { return }
        withAnimation(Motion.paper) { onAdd(text) }
        draft = ""
        addFocused = true
    }

    /// 메모지 종이 — 아래로 갈수록 살짝 그늘진다.
    private var paper: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [theme.p.memo, theme.p.memo.opacity(0.93)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.p.memoInk.opacity(0.06))
                    .frame(height: 14)
                    .blur(radius: 6)
            }
    }

    /// 위쪽 두 군데를 테이프로 붙였다.
    private var tape: some View {
        HStack {
            tapeStrip(angle: -7)
            Spacer()
            tapeStrip(angle: 6)
        }
        .padding(.horizontal, 26)
        .offset(y: -9)
    }

    private func tapeStrip(angle: Double) -> some View {
        Rectangle()
            .fill(theme.p.tape.opacity(0.62))
            .frame(width: 46, height: 15)
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.3), .clear, .white.opacity(0.18)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .rotationEffect(.degrees(angle))
            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
    }
}
