import SwiftUI

/// 설정의 "친구" 탭.
///
/// 내 이름과 초대 코드를 보여주고, 친구 코드를 넣어 등록하고, 등록한 친구를 나열한다.
/// 서버가 아직 없으면(`SupabaseConfig.isConfigured == false`) 안내만 띄운다.
struct FriendsSection: View {
    @EnvironmentObject private var store: StudyStore
    @EnvironmentObject private var friendSync: FriendSync
    let theme: Theme

    @State private var nameDraft = ""
    @State private var codeDraft = ""
    @State private var status: Status = .idle
    @FocusState private var codeFocused: Bool

    private enum Status: Equatable {
        case idle, searching, sent, notFound, alreadyFriend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if SupabaseConfig.isConfigured {
                meCard
                addCard
                requestList
                friendList
            } else {
                notConfigured
            }
        }
        .onAppear { nameDraft = store.profile.name }
        // 설정을 닫을 때 디스크에도, 서버에도 확실히 남긴다.
        .onDisappear {
            store.flush()
            friendSync.syncProfile()
        }
    }

    // MARK: 나

    private var meCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("나")

            VStack(alignment: .leading, spacing: 12) {
                // 이름
                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.p.inkSoft)
                    TextField("이름 (친구에게 보여요)", text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(Typo.body(14))
                        .foregroundStyle(theme.p.ink)
                        // 매 입력마다 로컬에 바로 반영한다 — Enter를 안 눌러도 안 사라진다.
                        .onChange(of: nameDraft) { _, new in store.setMyName(new) }
                        // 서버로 올리는 건 다 치고 났을 때만(입력마다 요청을 보내지 않는다).
                        .onSubmit { friendSync.syncProfile() }
                }

                Divider().overlay(theme.p.cardStroke)

                // 내 코드
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("내 초대 코드")
                            .font(Typo.body(11))
                            .foregroundStyle(theme.p.inkSoft)
                        Text(store.profile.code)
                            .font(Typo.plain(20, weight: .bold))
                            .monospaced()
                            .tracking(3)
                            .foregroundStyle(theme.p.ink)
                    }
                    Spacer()
                    Button {
                        copyCode()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.p.inkSoft)
                            .frame(width: 30, height: 30)
                            .glass(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .help("코드 복사")
                }
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    // MARK: 친구 추가

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("친구 추가", note: "친구의 초대 코드를 넣으세요")

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("코드 6자리", text: $codeDraft)
                        .textFieldStyle(.plain)
                        .font(Typo.plain(15, weight: .semibold))
                        .monospaced()
                        .foregroundStyle(theme.p.ink)
                        .focused($codeFocused)
                        .onSubmit(search)
                        .onChange(of: codeDraft) { _, new in
                            // 대문자 6자리로 다듬는다.
                            let cleaned = String(new.uppercased()
                                .filter { $0.isLetter || $0.isNumber }.prefix(6))
                            if cleaned != new { codeDraft = cleaned }
                            if status != .searching { status = .idle }
                        }

                    Button("찾기", action: search)
                        .buttonStyle(PrimaryButtonStyle(theme: theme))
                        .disabled(codeDraft.count < 6 || status == .searching)
                }

                statusLine
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .idle:
            EmptyView()
        case .searching:
            Text("보내는 중…")
                .font(Typo.body(11.5))
                .foregroundStyle(theme.p.inkSoft)
        case .sent:
            Text("요청을 보냈어요. 상대가 수락하면 친구가 돼요.")
                .font(Typo.body(11.5))
                .foregroundStyle(theme.p.accent)
        case .notFound:
            Text("그런 코드를 쓰는 사람이 없어요.")
                .font(Typo.body(11.5))
                .foregroundStyle(theme.p.brass)
        case .alreadyFriend:
            Text("이미 친구예요.")
                .font(Typo.body(11.5))
                .foregroundStyle(theme.p.inkSoft)
        }
    }

    // MARK: 받은 요청

    @ViewBuilder
    private var requestList: some View {
        if !friendSync.incoming.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("받은 요청 \(friendSync.incoming.count)개",
                              note: "수락하면 서로 친구가 돼요")

                VStack(spacing: 8) {
                    ForEach(friendSync.incoming) { person in
                        requestRow(person)
                    }
                }
            }
        }
    }

    private func requestRow(_ person: Friend) -> some View {
        HStack(spacing: 12) {
            avatar(person.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(person.name.isEmpty ? "이름 없음" : person.name)
                    .font(Typo.bodyStrong(13.5))
                    .foregroundStyle(theme.p.ink)
                Text("친구 요청")
                    .font(Typo.body(11))
                    .foregroundStyle(theme.p.accentSoft)
            }

            Spacer()

            Button("수락") {
                Task { await friendSync.accept(person) }
            }
            .buttonStyle(PrimaryButtonStyle(theme: theme))
        }
        .padding(10)
        .background(cardBackground)
    }

    // MARK: 친구 목록

    @ViewBuilder
    private var friendList: some View {
        if !store.friends.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("친구 \(store.friends.count)명")

                VStack(spacing: 8) {
                    ForEach(store.friends) { friend in
                        friendRow(friend)
                    }
                }
            }
        }
    }

    private func friendRow(_ friend: Friend) -> some View {
        HStack(spacing: 12) {
            avatar(friend.name)

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name.isEmpty ? "이름 없음" : friend.name)
                    .font(Typo.bodyStrong(13.5))
                    .foregroundStyle(theme.p.ink)
                Text(friend.code)
                    .font(Typo.plain(11))
                    .monospaced()
                    .foregroundStyle(theme.p.inkSoft)
            }

            Spacer()

            Button {
                Task { await friendSync.remove(friend) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.p.inkSoft.opacity(0.6))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(PressableStyle())
            .help("친구 삭제 — 서로에게서 사라져요")
        }
        .padding(10)
        .background(cardBackground)
    }

    private func avatar(_ name: String) -> some View {
        Circle()
            .fill(theme.p.accent.opacity(0.15))
            .frame(width: 32, height: 32)
            .overlay(
                Text(name.isEmpty ? "?" : String(name.prefix(1)))
                    .font(Typo.bodyStrong(14))
                    .foregroundStyle(theme.p.accent)
            )
    }

    // MARK: 설정 전

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("친구")
            VStack(alignment: .leading, spacing: 8) {
                Text("아직 서버가 연결되지 않았어요.")
                    .font(Typo.bodyStrong(13))
                    .foregroundStyle(theme.p.ink)
                Text("Supabase 프로젝트를 만들고 SupabaseConfig에 키를 넣으면\n친구 기능이 켜집니다.")
                    .font(Typo.body(12))
                    .foregroundStyle(theme.p.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
        }
    }

    // MARK: 동작

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.profile.code, forType: .string)
    }

    private func search() {
        let code = codeDraft
        guard code.count >= 6 else { return }
        status = .searching
        codeFocused = false

        Task {
            switch await friendSync.request(code: code) {
            case .sent:
                status = .sent
                codeDraft = ""
            case .alreadyFriend:
                status = .alreadyFriend
                codeDraft = ""
            case .notFound, .offline:
                status = .notFound
            }
        }
    }

    // MARK: 공통

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(theme.p.ink.opacity(theme.isDark ? 0.10 : 0.035))
    }

    private func sectionHeader(_ title: String, note: String? = nil) -> some View {
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
