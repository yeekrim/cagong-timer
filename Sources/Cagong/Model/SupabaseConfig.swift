import Foundation

/// Supabase 프로젝트 주소와 anon 키.
///
/// **이 두 값은 비밀이 아니다.** anon 키는 클라이언트 앱에 실려 배포되도록 설계된
/// 공개 키라서 레포에 있어도 된다. 진짜 보호는 서버의 RLS(행 수준 보안) 정책이 한다.
/// (그래도 지금은 익명 신원이라 보안이 느슨하다 — SUPABASE.md의 경고를 볼 것.)
///
/// 프로젝트를 만들고 아래 두 값을 채우면 친구 기능이 살아난다.
/// 비어 있으면 `FriendService`가 스스로 잠들어 아무 요청도 보내지 않는다.
enum SupabaseConfig {
    /// 예: "https://abcdefgh.supabase.co"
    static let url = "https://whemthrdbqsrufbgtond.supabase.co"

    /// 프로젝트 설정 → API → Project API keys → anon public
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndoZW10aHJkYnFzcnVmYmd0b25kIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU2NDY2MDgsImV4cCI6MjEwMTIyMjYwOH0.G0fZDx32CbAHNRy9cTWmlTYP322ShXE5x2WoBqcmjIg"

    /// 두 값이 다 채워졌는지. 하나라도 비면 친구 기능은 조용히 꺼진다.
    static var isConfigured: Bool {
        !url.isEmpty && !anonKey.isEmpty
    }

    static var restURL: URL? { URL(string: url + "/rest/v1") }
}
