import Foundation

/// Supabase와 이야기하는 창구. **SDK를 쓰지 않는다** — URLSession으로 REST만 부른다.
///
/// 실시간 구독(Realtime) 대신 **주기적으로 물어본다(polling).** Realtime은 Phoenix
/// 웹소켓 프로토콜을 직접 구현해야 해서 의존성 0 원칙과 안 맞고, 공부 이벤트는
/// 드물게 일어나므로 몇 초 간격 폴링으로 충분하다.
///
/// 설정이 비어 있으면(`SupabaseConfig.isConfigured == false`) 모든 메서드가 조용히
/// 아무것도 안 한다. 그래서 키를 넣기 전에도 앱은 멀쩡히 돈다.
actor FriendService {

    struct RemoteEvent: Decodable {
        let user_id: UUID
        let kind: String
        let created_at: Date
        let seconds: Double
        let goal_minutes: Int
    }

    private let session = URLSession(configuration: .ephemeral)

    /// 친구 이벤트를 어디까지 봤는지. 이 시각 이후 것만 새로 가져온다.
    private var lastSeen = Date()

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    // MARK: 요청 만들기

    private func request(path: String, query: String = "") -> URLRequest? {
        guard SupabaseConfig.isConfigured,
              let base = SupabaseConfig.restURL,
              let url = URL(string: base.absoluteString + path + (query.isEmpty ? "" : "?" + query))
        else { return nil }

        var req = URLRequest(url: url)
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    // MARK: 내 프로필 올리기

    /// 내 이름·코드를 서버에 올린다. 이미 있으면 갱신한다(upsert).
    func pushProfile(_ profile: Profile) async {
        guard var req = request(path: "/profiles") else { return }
        req.httpMethod = "POST"
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let body: [String: String] = [
            "id": profile.id.uuidString,
            "name": profile.name,
            "code": profile.code
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: req)
    }

    // MARK: 친구 찾기

    /// 초대 코드로 상대를 찾는다. 없으면 nil.
    func lookup(code: String) async -> Friend? {
        let normalized = code.uppercased().trimmingCharacters(in: .whitespaces)
        guard var req = request(
            path: "/profiles",
            query: "code=eq.\(normalized)&select=id,name,code&limit=1"
        ) else { return nil }
        req.httpMethod = "GET"

        guard let (data, _) = try? await session.data(for: req),
              let rows = try? decoder.decode([ProfileRow].self, from: data),
              let row = rows.first
        else { return nil }

        return Friend(id: row.id, name: row.name, code: row.code)
    }

    private struct ProfileRow: Decodable {
        let id: UUID
        let name: String
        let code: String
    }

    /// 여러 id의 프로필을 한 번에 가져온다. 친구 목록을 이름으로 채울 때 쓴다.
    func profiles(ids: [UUID]) async -> [Friend] {
        guard !ids.isEmpty else { return [] }
        let list = ids.map(\.uuidString).joined(separator: ",")
        guard var req = request(
            path: "/profiles",
            query: "id=in.(\(list))&select=id,name,code"
        ) else { return [] }
        req.httpMethod = "GET"

        guard let (data, _) = try? await session.data(for: req),
              let rows = try? decoder.decode([ProfileRow].self, from: data)
        else { return [] }
        return rows.map { Friend(id: $0.id, name: $0.name, code: $0.code) }
    }

    // MARK: 친구 관계
    //
    // 관계는 서버의 friendships가 진실이다. 로컬 친구 목록은 그 반영일 뿐.
    // 한 줄이 방향을 갖는다: requester가 addressee에게 요청한다.
    //   pending   — 보냈고 아직 수락 안 됨
    //   accepted  — 서로 친구
    //   removed   — 한쪽이 끊음 (양쪽에서 사라진다)

    private struct FriendshipRow: Decodable {
        let requester: UUID
        let addressee: UUID
    }

    /// 친구 요청을 보낸다. 이미 있으면 무시된다(같은 방향 유니크).
    func sendRequest(from me: UUID, to other: UUID) async {
        guard me != other, var req = request(path: "/friendships") else { return }
        req.httpMethod = "POST"
        req.setValue("resolution=ignore-duplicates", forHTTPHeaderField: "Prefer")

        let body: [String: String] = [
            "requester": me.uuidString,
            "addressee": other.uuidString,
            "status": "pending"
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: req)
    }

    /// 나를 향한 대기 중인 요청의 상대 id들. (내가 수락해야 할 사람들)
    ///
    /// **실패하면 nil이다.** 빈 배열(요청 없음)과 실패를 구분해야 한다 —
    /// 실패를 빈 값으로 취급하면 네트워크가 잠깐 끊길 때 로컬 상태를 지워버린다.
    func incomingRequesterIDs(me: UUID) async -> [UUID]? {
        guard var req = request(
            path: "/friendships",
            query: "addressee=eq.\(me.uuidString)&status=eq.pending&select=requester,addressee"
        ) else { return nil }
        req.httpMethod = "GET"

        guard let (data, _) = try? await session.data(for: req),
              let rows = try? decoder.decode([FriendshipRow].self, from: data)
        else { return nil }
        return rows.map(\.requester)
    }

    /// 수락된 친구들의 상대 id. 내가 보냈든 받았든 상관없이 모은다.
    /// **실패하면 nil** — 빈 배열(친구 없음)과 구분한다.
    func acceptedFriendIDs(me: UUID) async -> [UUID]? {
        let mine = me.uuidString
        guard var req = request(
            path: "/friendships",
            query: "or=(requester.eq.\(mine),addressee.eq.\(mine))"
                 + "&status=eq.accepted&select=requester,addressee"
        ) else { return nil }
        req.httpMethod = "GET"

        guard let (data, _) = try? await session.data(for: req),
              let rows = try? decoder.decode([FriendshipRow].self, from: data)
        else { return nil }
        // 나 아닌 쪽이 친구다.
        return rows.map { $0.requester == me ? $0.addressee : $0.requester }
    }

    /// 나에게 온 요청을 수락한다. requester → me 방향의 줄을 accepted로 바꾼다.
    func accept(me: UUID, requester: UUID) async {
        guard var req = request(
            path: "/friendships",
            query: "requester=eq.\(requester.uuidString)&addressee=eq.\(me.uuidString)"
        ) else { return }
        req.httpMethod = "PATCH"
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["status": "accepted"])
        _ = try? await session.data(for: req)
    }

    /// 관계를 끊는다. 양방향 줄을 removed로 바꿔 서로에게서 사라지게 한다.
    func remove(me: UUID, other: UUID) async {
        let a = me.uuidString, b = other.uuidString
        guard var req = request(
            path: "/friendships",
            query: "or=(and(requester.eq.\(a),addressee.eq.\(b)),"
                 + "and(requester.eq.\(b),addressee.eq.\(a)))"
        ) else { return }
        req.httpMethod = "PATCH"
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["status": "removed"])
        _ = try? await session.data(for: req)
    }

    // MARK: 현재 상태 (presence)

    /// 내 현재 상태를 서버에 올린다(있으면 갱신). 친구 탭이 이걸 읽는다.
    func pushPresence(_ p: Presence, for me: UUID) async {
        guard var req = request(path: "/statuses") else { return }
        req.httpMethod = "POST"
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let body: [String: Any] = [
            "user_id": me.uuidString,
            "state": p.state.rawValue,
            "day_key": p.dayKey,
            "seconds": p.seconds,
            "goal_minutes": p.goalMinutes,
            "updated_at": ISO8601DateFormatter().string(from: p.updatedAt)
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: req)
    }

    private struct StatusRow: Decodable {
        let user_id: UUID
        let state: String
        let day_key: String
        let seconds: Double
        let goal_minutes: Int
        let updated_at: Date
    }

    /// 친구들의 현재 상태를 가져온다. id → presence.
    func presences(of ids: [UUID]) async -> [UUID: Presence] {
        guard !ids.isEmpty else { return [:] }
        let list = ids.map(\.uuidString).joined(separator: ",")
        guard var req = request(
            path: "/statuses",
            query: "user_id=in.(\(list))"
                 + "&select=user_id,state,day_key,seconds,goal_minutes,updated_at"
        ) else { return [:] }
        req.httpMethod = "GET"

        guard let (data, _) = try? await session.data(for: req),
              let rows = try? decoder.decode([StatusRow].self, from: data)
        else { return [:] }

        var out: [UUID: Presence] = [:]
        for r in rows {
            out[r.user_id] = Presence(
                state: PresenceState(rawValue: r.state) ?? .idle,
                dayKey: r.day_key,
                seconds: r.seconds,
                goalMinutes: r.goal_minutes,
                updatedAt: r.updated_at
            )
        }
        return out
    }

    // MARK: 이벤트 보내기

    /// 내 이벤트를 서버에 남긴다. 친구들이 폴링으로 가져간다.
    func send(_ event: StudyEvent, from me: UUID) async {
        guard event.kind.notifiesFriends,
              var req = request(path: "/events") else { return }
        req.httpMethod = "POST"

        let body: [String: Any] = [
            "user_id": me.uuidString,
            "kind": event.kind.rawValue,
            "created_at": ISO8601DateFormatter().string(from: event.at),
            "seconds": event.seconds,
            "goal_minutes": event.goalMinutes
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await session.data(for: req)
    }

    // MARK: 친구 이벤트 가져오기

    /// 지난번 이후 친구들이 남긴 이벤트를 가져온다.
    /// 친구 목록이 비었거나 설정이 없으면 빈 배열.
    func poll(friendIDs: [UUID]) async -> [RemoteEvent] {
        guard !friendIDs.isEmpty else { return [] }

        let ids = friendIDs.map(\.uuidString).joined(separator: ",")
        let since = ISO8601DateFormatter().string(from: lastSeen)
        guard var req = request(
            path: "/events",
            query: "user_id=in.(\(ids))&created_at=gt.\(since)&order=created_at.asc"
        ) else { return [] }
        req.httpMethod = "GET"

        guard let (data, _) = try? await session.data(for: req),
              let rows = try? decoder.decode([RemoteEvent].self, from: data)
        else { return [] }

        // 가장 최근 것으로 커서를 민다. 같은 이벤트를 두 번 띄우지 않는다.
        if let newest = rows.map(\.created_at).max() {
            lastSeen = newest
        }
        return rows
    }
}
