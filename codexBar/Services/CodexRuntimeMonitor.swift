import Foundation
import AppKit
import SQLite3

final class CodexRuntimeMonitor {
    static let shared = CodexRuntimeMonitor()

    private let logsURL: URL
    private let codexBundleIdentifier = "com.openai.codex"
    private let busyWindowSeconds: Int64 = 20

    private init() {
        let home: URL
        if let pw = getpwuid(getuid()), let pwDir = pw.pointee.pw_dir {
            home = URL(fileURLWithPath: String(cString: pwDir))
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }
        logsURL = home.appendingPathComponent(".codex/logs_1.sqlite")
    }

    func runningCodexApplications() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: codexBundleIdentifier)
            .filter { !$0.isTerminated }
    }

    func hasRecentTaskActivity() -> Bool {
        guard !runningCodexApplications().isEmpty else { return false }
        guard let lastActivity = latestTaskActivityTimestamp() else { return false }

        let now = Int64(Date().timeIntervalSince1970)
        return now - lastActivity <= busyWindowSeconds
    }

    private func latestTaskActivityTimestamp() -> Int64? {
        guard FileManager.default.fileExists(atPath: logsURL.path) else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(logsURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT MAX(ts)
        FROM logs
        WHERE thread_id IS NOT NULL
          AND feedback_log_body LIKE '%session_task%'
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(statement, 0) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(statement, 0)
    }
}
