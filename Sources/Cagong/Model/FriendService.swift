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
