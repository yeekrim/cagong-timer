import SwiftUI

/// 친구 탭. 친구들이 지금 뭘 하고 있는지, 오늘 얼마나 했는지 한눈에 본다.
///
/// 상태는 `FriendSync.board`가 8초 폴링으로 채운다. 재는 중인 친구의 시간은
/// `TimelineView`로 1초마다 다시 그려 흐르는 것처럼 보이게 한다.
struct FriendsBoardView: View {
    @EnvironmentObject private var store: StudyStore
    @EnvironmentObject private var friendSync: FriendSync
    let theme: Theme

    /// 월간을 펼쳐 볼 친구. nil이면 시트 닫힘.
    @State private var opened: Friend?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            card
            Spacer(minLength: 8)
        }
        .sheet(item: $opened) { friend in
            FriendMonthlyView(friend: friend, theme: theme)
                .environmentObject(friendSync)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if friendSync.board.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(width: 420)
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .glass(
            RoundedRectangle(cornerRadius: Corner.card, style: .continuous),
            tint: theme.p.card,
            tintOpacity: 0.24
        )
    }

    // MARK: 머리

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(text: "Friends", theme: theme, color: theme.p.accentSoft)
                Text("같이 공부해요")
                    .font(Typo.title(21))
                    .foregroundStyle(theme.p.ink)
            }
            Spacer()
            if !friendSync.board.isEmpty {
                Text("\(studyingCount)명 공부 중")
                    .font(Typo.body(12))
                    .foregroundStyle(studyingCount > 0 ? theme.p.accent : theme.p.inkSoft)
            }
        }
        .padding(.bottom, 18)
    }

    private var studyingCount: Int {
        friendSync.board.filter { $0.activity == .studying }.count
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !SupabaseConfig.isConfigured {
                Text("아직 서버가 연결되지 않았어요.")
                    .font(Typo.bodyStrong(13.5))
                    .foregroundStyle(theme.p.ink)
            } else {
                Text("아직 친구가 없어요.")
                    .font(Typo.bodyStrong(13.5))
                    .foregroundStyle(theme.p.ink)
                Text("설정 → 친구에서 초대 코드로 친구를 추가하세요.")
                    .font(Typo.body(12.5))
                    .foregroundStyle(theme.p.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    // MARK: 목록

    private var list: some View {
        VStack(spacing: 10) {
            ForEach(friendSync.board) { status in
                row(status)
            }
        }
    }

    /// 재는 중인 친구만 1초마다 다시 그린다 — 나머지는 가만히 둔다.
    private func row(_ status: FriendStatus) -> some View {
        Group {
            if status.activity == .studying {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    rowBody(status, now: ctx.date)
                }
            } else {
                rowBody(status, now: status.anchoredAt)
            }
        }
    }

    private func rowBody(_ status: FriendStatus, now: Date) -> some View {
        HStack(spacing: 13) {
            avatar(status)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(status.friend.displayName)
                        .font(Typo.bodyStrong(14))
                        .foregroundStyle(theme.p.ink)
                    statusChip(status.activity)
                }

                progressLine(status, now: now)
            }
        }
        .padding(12)
        .background(SoftCardBackground(theme: theme, cornerRadius: 13))
        // 누르면 그 친구의 월간 기록을 연다.
        .contentShape(Rectangle())
        .onTapGesture { opened = status.friend }
        .help("\(status.friend.name.isEmpty ? "이 친구" : status.friend.name) 님의 월간 기록 보기")
    }

    private func avatar(_ status: FriendStatus) -> some View {
        ZStack(alignment: .bottomTrailing) {
            FriendAvatar(name: status.friend.name, size: 42, fontSize: 17, theme: theme)
            // 공부 중이면 초록 점을 찍어 살아있음을 표시한다.
            if status.activity == .studying {
                Circle()
                    .fill(theme.p.accent)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(theme.p.card, lineWidth: 2))
            }
        }
    }

    private func statusChip(_ activity: FriendActivity) -> some View {
        Text(activity.label)
            .font(Typo.body(10.5))
            .foregroundStyle(chipInk(activity))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(chipInk(activity).opacity(0.14)))
    }

    private func chipInk(_ activity: FriendActivity) -> Color {
        switch activity {
        case .studying: return theme.p.accent
        case .finished: return theme.p.brass
        case .resting, .away: return theme.p.inkSoft
        case .idle: return theme.p.inkSoft.opacity(0.7)
        }
    }

    private func progressLine(_ status: FriendStatus, now: Date) -> some View {
        HStack(spacing: 8) {
            ProgressCapsule(progress: status.progress(at: now), theme: theme)

            Text(timeLabel(status, now: now))
                .font(Typo.plain(11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.p.inkSoft)
                .fixedSize()
        }
    }

    private func timeLabel(_ status: FriendStatus, now: Date) -> String {
        if status.activity == .idle { return "—" }
        let done = TimeFormat.human(status.liveSeconds(at: now))
        guard status.goalMinutes > 0 else { return done }
        return "\(done) / \(TimeFormat.goal(minutes: status.goalMinutes))"
    }
}
