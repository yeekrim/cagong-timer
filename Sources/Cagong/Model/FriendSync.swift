import Foundation
import Combine

/// 내 이벤트를 서버로 보내고, 친구 이벤트를 주기적으로 가져와 알림으로 띄운다.
///
/// 앱이 켜져 있는 동안만 돈다. 공부 타이머라 공부 중엔 켜져 있고, 꺼져 있을 때
/// 온 친구 알림은 새벽에 굳이 안 울리는 편이 낫다.
///
/// 설정이 비어 있으면(`SupabaseConfig.isConfigured == false`) `start()`가 곧장
/// 돌아온다. 키를 넣기 전에는 아무 네트워크도 일어나지 않는다.
@MainActor
final class FriendSync: ObservableObject {

    /// 나에게 온, 아직 수락 안 한 친구 요청들. UI가 여기 보고 "수락" 버튼을 띄운다.
    /// 서버가 진실이라 저장하지 않는다 — 폴링할 때마다 다시 채운다.
    @Published private(set) var incoming: [Friend] = []

    /// 코드로 찾은 결과.
    enum RequestResult { case notFound, sent, alreadyFriend, offline }

    private let store: StudyStore
    private let service = FriendService()
    private var bag = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?

    /// 친구 이벤트·관계를 확인하는 간격. 공부 이벤트는 드무니 촘촘할 필요가 없다.
    private static let pollInterval: Duration = .seconds(8)

    init(store: StudyStore) {
        self.store = store
    }

    func start() {
        guard SupabaseConfig.isConfigured else { return }

        // 내 이름·코드를 올려둔다. 친구가 코드로 나를 찾을 수 있어야 하니까.
        let me = store.profile
        Task { await service.pushProfile(me) }

        // 내 이벤트가 생기면 서버로 흘려보낸다.
        store.events
            .sink { [weak self] event in
                guard let self else { return }
                let id = self.store.profile.id
                Task { await self.service.send(event, from: id) }
            }
            .store(in: &bag)

        // 관계와 이벤트를 주기적으로 확인한다.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshRelationships()
                await self?.pollEvents()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        bag.removeAll()
    }

    /// 내 이름을 바꾸면 서버에도 알린다.
    func syncProfile() {
        guard SupabaseConfig.isConfigured else { return }
        let me = store.profile
        Task { await service.pushProfile(me) }
    }

    // MARK: 친구 맺기

    /// 코드로 상대를 찾아 **요청을 보낸다.** 바로 친구가 되지 않는다 — 상대가 수락해야 한다.
    func request(code: String) async -> RequestResult {
        guard SupabaseConfig.isConfigured else { return .offline }
        let me = store.profile
        guard let found = await service.lookup(code: code), found.id != me.id else {
            return .notFound
        }
        if store.friend(found.id) != nil { return .alreadyFriend }

        await service.sendRequest(from: me.id, to: found.id)
        // 상대가 이미 나에게 요청해 둔 상태였다면, 내 요청이 곧 수락이 된다.
        await service.accept(me: me.id, requester: found.id)
        await refreshRelationships()
        return .sent
    }

    /// 나에게 온 요청을 수락한다. 이 순간부터 서로 친구다.
    func accept(_ friend: Friend) async {
        guard SupabaseConfig.isConfigured else { return }
        await service.accept(me: store.profile.id, requester: friend.id)
        await refreshRelationships()
    }

    /// 친구를 끊는다. 서버의 양방향 줄을 지우고 로컬에서도 뺀다.
    func remove(_ friend: Friend) async {
        store.removeFriend(friend.id)
        guard SupabaseConfig.isConfigured else { return }
        await service.remove(me: store.profile.id, other: friend.id)
        await refreshRelationships()
    }

    // MARK: 서버에서 당겨오기

    /// 수락된 친구 목록과 대기 중인 요청을 서버에서 가져와 반영한다.
    private func refreshRelationships() async {
        let me = store.profile.id

        // 수락된 친구 → 로컬 캐시를 서버 상태로 맞춘다.
        let acceptedIDs = await service.acceptedFriendIDs(me: me)
        let accepted = await service.profiles(ids: acceptedIDs)
        store.syncFriends(accepted)

        // 대기 중인 요청 → 이미 친구인 사람은 뺀다.
        let pendingIDs = await service.incomingRequesterIDs(me: me)
            .filter { id in !accepted.contains { $0.id == id } }
        incoming = await service.profiles(ids: pendingIDs)
    }

    private func pollEvents() async {
        let events = await service.poll(friendIDs: store.friendIDs)
        for remote in events {
            guard let friend = store.friend(remote.user_id),
                  let kind = StudyEventKind(rawValue: remote.kind)
            else { continue }

            let event = StudyEvent(
                kind: kind,
                at: remote.created_at,
                dayKey: DateKey.string(from: remote.created_at),
                seconds: remote.seconds,
                goalMinutes: remote.goal_minutes
            )
            Notifier.shared.post(title: "친구 소식", body: event.friendBody(name: friend.name))
        }
    }
}
