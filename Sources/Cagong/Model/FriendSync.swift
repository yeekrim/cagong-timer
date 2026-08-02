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

    private let store: StudyStore
    private let service = FriendService()
    private var bag = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?

    /// 친구 이벤트를 확인하는 간격. 공부 이벤트는 드무니 촘촘할 필요가 없다.
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

        // 친구 이벤트를 주기적으로 가져온다.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
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

    /// 초대 코드로 친구를 찾는다. UI에서 부른다.
    func lookup(code: String) async -> Friend? {
        await service.lookup(code: code)
    }

    private func pollOnce() async {
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
