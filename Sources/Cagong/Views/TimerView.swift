import SwiftUI

/// 측정 화면.
///
/// 위에 날짜와 현재 시각, 아래에 잔·시간·시작 버튼, 오른쪽에 메모지.
///
/// 날짜는 **이미 오늘로 정해져 있다.** 앱을 켜고 시작만 누르면 끝이고,
/// 어제를 재야 할 때(새벽까지 공부한 경우)만 날짜를 눌러 바꾼다.
struct TimerView: View {
    @EnvironmentObject private var store: StudyStore
    let theme: Theme
    /// 화면을 넘어갈 때 잔이 함께 날아가도록 공유하는 이름 공간
    let namespace: Namespace.ID

    @State private var confirmingEnd = false
    @State private var cardHovered = false
    @State private var pickingDate = false
    @State private var pickingGoal = false

    var body: some View {
        // 창이 좁으면 메모지를 카드 아래로 내린다.
        //
        // 카드(468)와 메모지(268)는 폭이 고정이라 나란히 두면 714가 필요하다.
        // 자리가 없을 때 겹치거나 잘리는 대신 세로로 쌓으면 468이면 된다.
        ViewThatFits(in: .horizontal) {
            layout(stacked: false)
            layout(stacked: true)
        }
        .confirmationDialog(
            store.isMeasuringPastDay ? "어제 기록을 마칠까요?" : "오늘 공부를 마칠까요?",
            isPresented: $confirmingEnd,
            titleVisibility: .visible
        ) {
            Button("네, 자러 갈래요", role: .destructive) {
                withAnimation(Motion.screen) { store.endDay() }
            }
            Button("아뇨, 계속 할게요", role: .cancel) {}
        } message: {
            Text("기록은 그대로 남습니다. 마음이 바뀌면 다시 시작할 수 있어요.")
        }
    }

    /// - Parameter stacked: 메모지를 카드 옆이 아니라 아래에 둘지.
    private func layout(stacked: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            dateBar
                .frame(width: Self.cardWidth)
                .padding(.bottom, 12)

            if stacked {
                VStack(spacing: 16) {
                    mainCard
                    memo
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    mainCard
                    memo
                        .padding(.leading, -22)
                        .padding(.top, 34)
                }
            }

            endButton
                .padding(.top, 26)

            Spacer(minLength: 8)
        }
    }

    // MARK: 날짜 · 시각

    /// 날짜 표시가 곧 날짜 선택기다.
    ///
    /// 고르는 걸 별도 단계로 만들면 매일 쓰는 사람에게 세금이 된다.
    /// 평소엔 그냥 오늘 날짜를 읽는 글자이고, 눌렀을 때만 선택지가 열린다.
    private var dateBar: some View {
        HStack(spacing: 10) {
            // 칩은 재는 날짜를 보여준다. 그 날짜는 저절로 바뀌지 않으므로
            // 시간이 흐른다고 다시 그릴 이유가 없다.
            dateChip

            // 배지와 시계는 다르다. **자정을 넘기면 재는 날짜가 가만히 있어도
            // '어제'가 되므로** 배지가 저절로 떠야 한다.
            //
            // store는 이제 초 단위로 알리지 않는다(그러면 화면 전체가 다시 평가된다).
            // 그래서 여기서 직접 시간을 보고, 이 줄만 다시 그린다.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let label = pastDayLabel(at: context.date)

                HStack(spacing: 10) {
                    if let label {
                        Text(label)
                            .font(Typo.body(11.5))
                            .foregroundStyle(theme.isDark ? Color(hex: 0x14161E) : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(theme.p.accent))
                            .transition(.opacity.combined(with: .scale))
                    }

                    Spacer()

                    Text(KoDate.clock(context.date))
                        .font(Typo.stamp(13))
                        .foregroundStyle(theme.p.inkSoft)
                        .monospacedDigit()
                }
                .animation(Motion.button, value: label)
            }
        }
    }

    /// 재는 날짜가 지금 기준으로 지난 날이면 뭐라고 알릴지. 오늘이면 nil.
    ///
    /// 자정을 넘겨 계속 재는 경우가 이 함수의 존재 이유다 — 고른 날짜는 그대로인데
    /// 바깥의 "오늘"만 넘어가므로, 시간을 인자로 받아야 제때 바뀐다.
    private func pastDayLabel(at now: Date) -> String? {
        let key = store.measuringKey
        guard key != DateKey.string(from: now) else { return nil }

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        if key == DateKey.string(from: yesterday) { return "어제 기록 중" }

        // 24시간 넘게 이어 재면 그제까지 밀릴 수 있다. 그때도 틀린 말을 하지 않는다.
        return (DateKey.date(from: key).map { KoDate.short($0) } ?? key) + " 기록 중"
    }

    private var dateChip: some View {
        Button { pickingDate = true } label: {
            HStack(spacing: 7) {
                Text(KoDate.dayWithWeekday(measuringDate))
                    .font(Typo.bodyStrong(13))
                    .foregroundStyle(theme.p.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(theme.p.inkSoft)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .glass(Capsule())
        }
        .buttonStyle(PressableStyle())
        .popover(isPresented: $pickingDate, arrowEdge: .bottom) {
            datePicker
        }
        .help("기록할 날짜를 고릅니다")
    }

    /// 오늘과 어제만. 그저께부터는 아예 선택지에 없다.
    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([DateKey.today(), DateKey.yesterday()], id: \.self) { key in
                let isOn = key == store.measuringKey
                let date = DateKey.date(from: key) ?? Date()

                Button {
                    withAnimation(Motion.screen) { store.setMeasuringDate(key) }
                    pickingDate = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(isOn ? theme.p.accent : theme.p.inkSoft.opacity(0.5))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(key == DateKey.today() ? "오늘" : "어제")
                                .font(Typo.bodyStrong(13))
                                .foregroundStyle(theme.p.ink)
                            Text(KoDate.dayWithWeekday(date))
                                .font(Typo.body(11.5))
                                .foregroundStyle(theme.p.inkSoft)
                        }

                        Spacer(minLength: 20)

                        Text(TimeFormat.human(store.seconds(for: key)))
                            .font(Typo.stamp(12))
                            .foregroundStyle(theme.p.inkSoft)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }

            Text("그제부터는 고칠 수 없어요.")
                .font(Typo.body(11))
                .foregroundStyle(theme.p.inkSoft.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
        .frame(width: 250)
        .background(theme.p.card)
    }

    private var measuringDate: Date {
        DateKey.date(from: store.measuringKey) ?? Date()
    }

    // MARK: 본 카드

    /// 시간 글자 크기. 자리폭이 고정이라 표시 폭을 미리 계산할 수 있다.
    /// 숫자 6칸 × 0.60 + 콜론 2칸 × 0.30 = 4.2배.
    private static let timeSize: CGFloat = 60
    private static var timeWidth: CGFloat { timeSize * 4.2 }

    /// 카드 폭. 좁은 창에서도 이 값은 줄이지 않는다 —
    /// 여기서 한 칸이라도 깎으면 시간 숫자가 카드를 뚫고 나간다.
    static let cardWidth: CGFloat = 468

    /// 카드는 한 덩어리다.
    /// 카드 468 − 좌우 여백 56 − 잔 120 − 간격 22 = 270 ≥ 4.2 × 60 = 252.
    private var mainCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Eyebrow(
                text: store.isRunning ? "Measuring" : "Paused",
                theme: theme,
                color: store.isRunning ? theme.p.accent : theme.p.inkSoft
            )
            .animation(Motion.button, value: store.isRunning)

            HStack(alignment: .center, spacing: 22) {
                DrinkGlass(
                    running: store.isRunning,
                    theme: theme,
                    drink: store.drink,
                    side: 120
                )
                .matchedGeometryEffect(id: "cup", in: namespace)

                // 흐르는 시간은 여기서만 다시 그린다.
                //
                // 예전에는 store가 매초 변경을 알렸고, 그러면 배경·메모지·유리 표면까지
                // 화면 전체가 다시 평가됐다. 숫자 한 칸 때문에 초당 세 번씩.
                // TimelineView는 자기 안쪽만 굴리므로 나머지는 가만히 있는다.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 11) {
                        TimeDisplay(
                            seconds: store.displaySeconds(at: context.date),
                            size: Self.timeSize,
                            color: theme.p.ink,
                            colonColor: theme.p.inkSoft.opacity(0.5)
                        )
                        .padding(.leading, -4)

                        goalBar(progress: store.goalProgress(
                            for: store.measuringKey, at: context.date
                        ))
                    }
                }
            }

            startButton
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(width: Self.cardWidth, alignment: .leading)
        .glass(
            RoundedRectangle(cornerRadius: 22, style: .continuous),
            tint: theme.p.card,
            tintOpacity: 0.20,
            lifted: cardHovered
        )
        .onHover { inside in
            withAnimation(Motion.card) { cardHovered = inside }
        }
    }

    private func goalBar(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.p.ink.opacity(theme.isDark ? 0.16 : 0.08))
                    .frame(height: 4)

                GeometryReader { g in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [theme.p.accentSoft, theme.p.accent],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: g.size.width * progress, height: 4)
                }
                .frame(height: 4)
            }
            .frame(width: Self.timeWidth)
            .animation(Motion.card, value: progress)

            goalCaption(progress: progress)
        }
    }

    /// 목표 문구가 곧 목표 설정기다. 날짜 칩과 같은 규칙 —
    /// 평소엔 읽는 글자이고, 눌렀을 때만 고칠 수 있게 열린다.
    private func goalCaption(progress: Double) -> some View {
        Button { pickingGoal = true } label: {
            HStack(spacing: 5) {
                Text(goalText(progress: progress))
                    .font(Typo.body(12))
                    .foregroundStyle(theme.p.inkSoft)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.p.inkSoft.opacity(0.7))
            }
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .popover(isPresented: $pickingGoal, arrowEdge: .bottom) { goalPicker }
        .help("이 날의 목표를 정합니다")
    }

    private func goalText(progress: Double) -> String {
        let goal = store.goalMinutes(for: store.measuringKey)
        let text = goal % 60 == 0 ? "\(goal / 60)시간" : "\(goal / 60)시간 \(goal % 60)분"
        if progress >= 1 { return "목표 \(text) 달성" }
        return "목표 \(text) 중 \(Int(progress * 100))%"
    }

    /// 그날치 목표만 바꾼다. 다른 날은 건드리지 않는다.
    private var goalPicker: some View {
        let minutes = store.goalMinutes(for: store.measuringKey)

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(KoDate.dayWithWeekday(measuringDate)) 목표")
                    .font(Typo.bodyStrong(13))
                    .foregroundStyle(theme.p.ink)
                Text("이 날에만 적용됩니다")
                    .font(Typo.body(11))
                    .foregroundStyle(theme.p.inkSoft.opacity(0.8))
            }

            HStack {
                Text(minutes % 60 == 0 ? "\(minutes / 60)시간"
                                       : "\(minutes / 60)시간 \(minutes % 60)분")
                    .font(Typo.title(19))
                    .foregroundStyle(theme.p.ink)
                    .contentTransition(.numericText())
                    .animation(Motion.digit, value: minutes)

                Spacer()

                HStack(spacing: 6) {
                    goalStep("minus", to: minutes - 30)
                    goalStep("plus", to: minutes + 30)
                }
            }

            Slider(
                value: Binding(
                    get: { Double(minutes) },
                    set: { store.setGoal(minutes: Int(($0 / 30).rounded()) * 30) }
                ),
                in: 30...720,
                step: 30
            )
            .tint(theme.p.accent)
        }
        .padding(18)
        .frame(width: 288)
        .background(theme.p.card)
    }

    private func goalStep(_ icon: String, to minutes: Int) -> some View {
        Button {
            withAnimation(Motion.button) { store.setGoal(minutes: minutes) }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.p.inkSoft)
                .frame(width: 25, height: 25)
                .background(Circle().fill(theme.p.ink.opacity(0.07)))
        }
        .buttonStyle(PressableStyle())
    }

    private var startButton: some View {
        Button(store.isRunning ? "일시정지" : (store.displaySeconds() > 0 ? "이어서 하기" : "시작")) {
            withAnimation(Motion.button) { store.toggleRunning() }
        }
        .buttonStyle(PrimaryButtonStyle(theme: theme))
        .keyboardShortcut(.return, modifiers: .command)
        .help(store.isRunning ? "일시정지 (⌘↩)" : "시작 (⌘↩)")
    }

    // MARK: 메모지

    /// 지난 날의 할 일은 글자를 고칠 수 없다. 체크만 열려 있다.
    ///
    /// 루틴 고정도 오늘에서만 바꾼다 — 어제의 압정을 눌러 내일이 바뀌면 헷갈린다.
    private var memo: some View {
        MemoSlip(
            todos: store.todos,
            theme: theme,
            onToggle: { store.toggleTodo($0) },
            onAdd: store.canEditTodoText ? { store.addTodo($0) } : nil,
            onRemove: store.canEditTodoText ? { store.removeTodo($0) } : nil,
            onPin: store.canEditTodoText ? { store.togglePin($0) } : nil
        )
    }

    // MARK: 마무리

    private var endButton: some View {
        Button("Zzz") { confirmingEnd = true }
            .buttonStyle(GhostButtonStyle(theme: theme))
            .help("그날 몫을 마무리합니다. 기록은 그대로 남고 다시 시작할 수 있어요")
    }
}
