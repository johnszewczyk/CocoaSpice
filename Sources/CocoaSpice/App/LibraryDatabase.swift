import Foundation
import OSLog
import SQLite3

/// Namespace for CocoaSpice's narrow, read-only catalog queries. The catalog
/// is created and maintained by ScanSong; this type never opens a writable
/// SQLite connection or performs schema maintenance.
final class LibraryDatabase: @unchecked Sendable {
    static let schemaVersion = 23
    static let performanceLogger = Logger(
        subsystem: "com.local.cocoaspice",
        category: "catalog-read"
    )

    let databaseURL: URL

    convenience init() throws {
        self.init(databaseURL: try Self.configuredDatabaseURL())
    }

    init(databaseURL: URL) {
        self.databaseURL = databaseURL.standardizedFileURL
    }

    var isReadOnly: Bool { true }

    static func defaultDatabaseURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return base
            .appendingPathComponent("CocoaSpice", isDirectory: true)
            .appendingPathComponent("Library.sqlite", isDirectory: false)
    }

    static func configuredDatabaseURL(defaults: UserDefaults = .standard) throws -> URL {
        guard let storedPath = defaults.string(forKey: AppDefaultsKey.libraryDatabasePath)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !storedPath.isEmpty else {
            return try defaultDatabaseURL()
        }
        guard (storedPath as NSString).isAbsolutePath else {
            throw NSError(
                domain: "LibraryDatabase",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The configured library database path must be absolute."]
            )
        }
        return URL(fileURLWithPath: storedPath).standardizedFileURL
    }

    static func databaseError(handle: OpaquePointer?) -> NSError {
        let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
        let extendedCode = handle.map { sqlite3_extended_errcode($0) } ?? SQLITE_ERROR
        return NSError(
            domain: "LibraryDatabase",
            code: Int(extendedCode),
            userInfo: [NSLocalizedDescriptionKey: "\(message) (SQLite extended code \(extendedCode))"]
        )
    }
}

enum SQLiteValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case null
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

func sqliteBind(_ value: SQLiteValue, to statement: OpaquePointer?, at index: Int32) {
    switch value {
    case let .int(number):
        sqlite3_bind_int64(statement, index, number)
    case let .double(number):
        sqlite3_bind_double(statement, index, number)
    case let .text(string):
        sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
    case .null:
        sqlite3_bind_null(statement, index)
    }
}

func sqliteString(_ statement: OpaquePointer?, index: Int32) -> String {
    guard let value = sqlite3_column_text(statement, index) else { return "" }
    return String(cString: value)
}

func sqliteNullableString(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard let value = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: value)
}
