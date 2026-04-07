import Foundation
import SQLite3

public enum SQLiteOpenMode: Sendable {
    case readOnly
    case readWriteCreate
}

public enum SQLiteValue: Sendable, Equatable {
    case integer(Int64)
    case double(Double)
    case text(String)
    case null

    var stringValue: String? {
        switch self {
        case let .text(value):
            return value
        case let .integer(value):
            return String(value)
        case let .double(value):
            return String(value)
        case .null:
            return nil
        }
    }

    var intValue: Int? {
        switch self {
        case let .integer(value):
            return Int(value)
        case let .double(value):
            return Int(value)
        case let .text(value):
            return Int(value)
        case .null:
            return nil
        }
    }

    var int64Value: Int64? {
        switch self {
        case let .integer(value):
            return value
        case let .double(value):
            return Int64(value)
        case let .text(value):
            return Int64(value)
        case .null:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case let .integer(value):
            return Double(value)
        case let .double(value):
            return value
        case let .text(value):
            return Double(value)
        case .null:
            return nil
        }
    }
}

public final class SQLiteConnection {
    private var handle: OpaquePointer?

    public init(url: URL, mode: SQLiteOpenMode = .readOnly) throws {
        var database: OpaquePointer?
        let flags: Int32
        switch mode {
        case .readOnly:
            flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        case .readWriteCreate:
            flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        }

        let result = sqlite3_open_v2(url.path, &database, flags, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Failed to open database"
            if let database {
                sqlite3_close(database)
            }
            throw OpenCodeDataError.sqlite(message)
        }

        self.handle = database
        sqlite3_busy_timeout(database, 1_000)
    }

    deinit {
        guard let handle else { return }
        sqlite3_close(handle)
    }

    public func execute(_ sql: String) throws {
        guard let handle else { throw OpenCodeDataError.sqlite("Database already closed") }
        let result = sqlite3_exec(handle, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw OpenCodeDataError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
    }

    public func query(_ sql: String) throws -> [[String: SQLiteValue]] {
        guard let handle else { throw OpenCodeDataError.sqlite("Database already closed") }
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw OpenCodeDataError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }

        defer { sqlite3_finalize(statement) }

        let columnCount = sqlite3_column_count(statement)
        var rows: [[String: SQLiteValue]] = []

        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                var row: [String: SQLiteValue] = [:]
                for index in 0 ..< columnCount {
                    let columnName = String(cString: sqlite3_column_name(statement, index))
                    row[columnName] = value(at: index, statement: statement)
                }
                rows.append(row)
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                throw OpenCodeDataError.sqlite(String(cString: sqlite3_errmsg(handle)))
            }
        }

        return rows
    }

    public func tableExists(_ tableName: String) throws -> Bool {
        let escaped = tableName.replacingOccurrences(of: "'", with: "''")
        let rows = try query("SELECT name FROM sqlite_master WHERE type = 'table' AND name = '\(escaped)' LIMIT 1")
        return !rows.isEmpty
    }

    public func columnNames(for tableName: String) throws -> Set<String> {
        let escaped = tableName.replacingOccurrences(of: "'", with: "''")
        let rows = try query("PRAGMA table_info('\(escaped)')")
        return Set(rows.compactMap { $0["name"]?.stringValue })
    }

    private func value(at index: Int32, statement: OpaquePointer) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .double(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            return .text(String(cString: sqlite3_column_text(statement, index)))
        default:
            return .null
        }
    }
}
