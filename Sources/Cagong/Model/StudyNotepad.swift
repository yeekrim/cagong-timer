import Combine
import Foundation
import OSLog
import SQLite3

@MainActor
final class StudyNotepad: ObservableObject {
    @Published var text = ""
    private var savedText = ""
    private let databaseURL: URL
    private let logger = Logger(subsystem: "com.yeekrim.cagong", category: "notepad")

    init(databaseURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.databaseURL = databaseURL ?? support
            .appendingPathComponent("Cagong", isDirectory: true)
            .appendingPathComponent("notepad.sqlite3")

        guard FileManager.default.fileExists(atPath: self.databaseURL.path) else { return }
        do {
            text = try withStatement("SELECT body FROM notepad WHERE id = 1") { statement in
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    guard let bytes = sqlite3_column_text(statement, 0) else { throw DatabaseError() }
                    let count = Int(sqlite3_column_bytes(statement, 0))
                    return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
                case SQLITE_DONE:
                    return ""
                default:
                    throw DatabaseError()
                }
            }
            savedText = text
        } catch {
            logger.error("Failed to load the study notepad")
        }
    }

    func save() throws {
        guard text != savedText else { return }

        let sql = """
            INSERT INTO notepad (id, body) VALUES (1, ?)
            ON CONFLICT(id) DO UPDATE SET body = excluded.body
            """
        try withStatement(sql) { statement in
            try text.utf8CString.withUnsafeBufferPointer { bytes in
                guard let length = Int32(exactly: bytes.count - 1),
                      sqlite3_bind_text(statement, 1, bytes.baseAddress, length, nil) == SQLITE_OK
                else { throw DatabaseError() }
                // SQLite borrows the buffer until it is unbound.
                defer { sqlite3_clear_bindings(statement) }
                guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError() }
            }
        }
        savedText = text
    }

    private func withStatement<Result>(
        _ sql: String,
        _ body: (OpaquePointer) throws -> Result
    ) throws -> Result {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        defer { sqlite3_close(database) }
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            throw DatabaseError()
        }

        let schema = "CREATE TABLE IF NOT EXISTS notepad (id INTEGER PRIMARY KEY CHECK (id = 1), body TEXT NOT NULL)"
        guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else { throw DatabaseError() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseError()
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private struct DatabaseError: LocalizedError {
        var errorDescription: String? { "메모장 데이터베이스에 접근할 수 없습니다." }
    }
}
