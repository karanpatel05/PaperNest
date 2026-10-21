import Foundation
import SQLite3

/// A minimal wrapper over the system SQLite library (no third-party
/// dependency). Not thread-safe by itself; `LibraryStore` confines each
/// connection to one actor.
final class SQLiteDatabase {
    private(set) var handle: OpaquePointer?

    enum OpenMode {
        case readWriteCreate
        case readOnly
    }

    init(path: String, mode: OpenMode = .readWriteCreate) throws {
        let flags: Int32 = switch mode {
        case .readWriteCreate: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        case .readOnly: SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        }
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close_v2(db)
            throw StoreError.database(code: rc, message: message)
        }
        handle = db
        sqlite3_busy_timeout(db, 5_000)
        sqlite3_extended_result_codes(db, 1)
    }

    deinit {
        close()
    }

    func close() {
        if let handle {
            sqlite3_close_v2(handle)
        }
        handle = nil
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw StoreError.database(code: rc, message: message)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else {
            throw StoreError.database(code: rc, message: lastErrorMessage)
        }
        return Statement(stmt, db: self)
    }

    /// Executes one statement with `values` bound; returns the changed row count.
    @discardableResult
    func run(_ sql: String, _ values: [SQLValue] = []) throws -> Int {
        let stmt = try prepare(sql)
        try stmt.bind(values)
        while try stmt.step() {}
        return Int(sqlite3_changes(handle))
    }

    func query<T>(_ sql: String, _ values: [SQLValue] = [], map: (Statement) throws -> T) throws -> [T] {
        let stmt = try prepare(sql)
        try stmt.bind(values)
        var rows: [T] = []
        while try stmt.step() {
            rows.append(try map(stmt))
        }
        return rows
    }

    /// `BEGIN IMMEDIATE` takes the write lock up front so a transaction never
    /// fails halfway with SQLITE_BUSY. Anything thrown rolls everything back.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var userVersion: Int {
        get throws {
            try query("PRAGMA user_version") { Int($0.int64(0)) }.first ?? 0
        }
    }

    func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    var lastErrorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "closed"
    }
}

enum SQLValue {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)

    static func optionalText(_ s: String?) -> SQLValue { s.map(SQLValue.text) ?? .null }
    static func optionalDouble(_ d: Double?) -> SQLValue { d.map(SQLValue.double) ?? .null }
    static func bool(_ b: Bool) -> SQLValue { .int(b ? 1 : 0) }
    /// Dates are stored as `timeIntervalSinceReferenceDate`, Date's own
    /// representation, so they round-trip bit-exactly.
    static func date(_ d: Date) -> SQLValue { .double(d.timeIntervalSinceReferenceDate) }
    static func optionalDate(_ d: Date?) -> SQLValue { d.map { .double($0.timeIntervalSinceReferenceDate) } ?? .null }
}

/// SQLite asks for a destructor for bound text/blobs; TRANSIENT makes it copy.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class Statement {
    private let stmt: OpaquePointer
    private unowned let db: SQLiteDatabase

    init(_ stmt: OpaquePointer, db: SQLiteDatabase) {
        self.stmt = stmt
        self.db = db
    }

    deinit {
        sqlite3_finalize(stmt)
    }

    func bind(_ values: [SQLValue]) throws {
        for (offset, value) in values.enumerated() {
            let i = Int32(offset + 1)
            let rc: Int32 = switch value {
            case .null: sqlite3_bind_null(stmt, i)
            case .int(let v): sqlite3_bind_int64(stmt, i, v)
            case .double(let v): sqlite3_bind_double(stmt, i, v)
            case .text(let v): sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT)
            case .blob(let v): v.withUnsafeBytes { buf in
                sqlite3_bind_blob(stmt, i, buf.baseAddress, Int32(buf.count), SQLITE_TRANSIENT)
            }
            }
            guard rc == SQLITE_OK else { throw StoreError.database(code: rc, message: db.lastErrorMessage) }
        }
    }

    /// Returns true while a row is available.
    func step() throws -> Bool {
        let rc = sqlite3_step(stmt)
        switch rc {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw StoreError.database(code: rc, message: db.lastErrorMessage)
        }
    }

    func isNull(_ col: Int32) -> Bool { sqlite3_column_type(stmt, col) == SQLITE_NULL }
    func int64(_ col: Int32) -> Int64 { sqlite3_column_int64(stmt, col) }
    func int(_ col: Int32) -> Int { Int(sqlite3_column_int64(stmt, col)) }
    func double(_ col: Int32) -> Double { sqlite3_column_double(stmt, col) }
    func bool(_ col: Int32) -> Bool { sqlite3_column_int64(stmt, col) != 0 }
    func date(_ col: Int32) -> Date { Date(timeIntervalSinceReferenceDate: double(col)) }
    func optionalDate(_ col: Int32) -> Date? { isNull(col) ? nil : date(col) }

    func text(_ col: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: c)
    }

    func optionalText(_ col: Int32) -> String? { isNull(col) ? nil : text(col) }

    func blob(_ col: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(stmt, col))
        guard count > 0, let ptr = sqlite3_column_blob(stmt, col) else { return Data() }
        return Data(bytes: ptr, count: count)
    }
}
