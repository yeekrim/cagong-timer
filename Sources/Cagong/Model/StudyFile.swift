import Foundation

/// 저장 파일(study-data.json)을 읽고 쓴다. 상태는 없다.
///
/// `StudyStore`가 메인 스레드에서 값만 복사해 넘기면, 인코딩과 디스크 쓰기는
/// 백그라운드 큐에서 이 함수가 한다. 그래서 메인 액터에 묶이지 않는다.
enum StudyFile {
    /// 사람이 읽기 좋은 들여쓰기는 넣지 않는다 — 파일이 세 배로 커지고
    /// 인코딩도 그만큼 느려진다. 키 정렬만 유지해 매번 같은 바이트가 나오게 한다.
    static func write(_ data: AppData, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(data) else { return }
        try? encoded.write(to: url, options: .atomic)
    }

    static func load(from url: URL) -> AppData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppData.self, from: raw)
    }
}
