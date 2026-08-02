import Foundation

/// 이 기기의 신원(id·code)을 **UserDefaults에** 영구 보관한다.
///
/// 신원은 절대 바뀌면 안 된다 — 서버의 친구 관계가 이 id에 묶이기 때문이다.
/// 예전엔 신원을 study-data.json 안에만 뒀는데, 그 파일이 어떤 이유로든 프로필
/// 없이 다시 써지면 새 id가 태어나 친구 관계가 통째로 끊겼다(빌드마다 초기화).
///
/// UserDefaults는 저장 파일과 별개라, 파일이 초기화돼도 신원은 살아남는다.
enum DeviceIdentity {
    private static let d = UserDefaults.standard
    private static let idKey = "cagong.identity.id"
    private static let codeKey = "cagong.identity.code"

    /// 저장된 신원을 돌려준다. 없으면 파일에 있던 신원을 이어받고,
    /// 그것도 없으면 새로 만들어 **한 번만** 박아둔다.
    static func resolve(migratingFrom fileProfile: Profile) -> (id: UUID, code: String) {
        if let idStr = d.string(forKey: idKey), let id = UUID(uuidString: idStr),
           let code = d.string(forKey: codeKey), !code.isEmpty {
            return (id, code)
        }

        // 처음이다. 파일에 신원이 있으면 그걸 이어받아 잠근다(기존 사용자 보존).
        let id = fileProfile.id
        let code = fileProfile.code.isEmpty ? Profile.newCode() : fileProfile.code
        d.set(id.uuidString, forKey: idKey)
        d.set(code, forKey: codeKey)
        return (id, code)
    }

    /// 신원을 특정 값으로 못박는다(복구용).
    static func override(id: UUID, code: String) {
        d.set(id.uuidString, forKey: idKey)
        d.set(code, forKey: codeKey)
    }
}
