import Foundation

/// A small, streaming ZIP writer (PKWARE APPNOTE 6.3, "stored" entries).
///
/// JPEG and PNG data is already compressed, so storing avoids burning CPU for
/// no gain. Entries are written one at a time so memory stays bounded by the
/// largest single file. ZIP64 is not implemented; archives over 4 GiB fail
/// with `ExportError.archiveTooLarge` instead of producing a corrupt file.
public final class ZipWriter {
    private struct Entry {
        let name: Data
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
        let dosTime: UInt16
        let dosDate: UInt16
    }

    private let handle: FileHandle
    private var entries: [Entry] = []
    private var offset: UInt64 = 0
    private let date: Date

    public init(url: URL, date: Date = Date()) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw ExportError.writeFailed }
        handle = try FileHandle(forWritingTo: url)
        self.date = date
    }

    public func addFile(named name: String, data: Data) throws {
        let nameData = Data(name.utf8)
        guard data.count < UInt32.max, offset + UInt64(data.count) + 30 + UInt64(nameData.count) < UInt64(UInt32.max) else {
            throw ExportError.archiveTooLarge
        }
        let (time, day) = Self.dosDateTime(date)
        let entry = Entry(name: nameData, crc: CRC32.checksum(data), size: UInt32(data.count), offset: UInt32(offset), dosTime: time, dosDate: day)

        var header = Data()
        header.appendLE(UInt32(0x0403_4B50))
        header.appendLE(UInt16(20))           // version needed
        header.appendLE(UInt16(1 << 11))      // flags: UTF-8 names
        header.appendLE(UInt16(0))            // method: stored
        header.appendLE(entry.dosTime)
        header.appendLE(entry.dosDate)
        header.appendLE(entry.crc)
        header.appendLE(entry.size)           // compressed size
        header.appendLE(entry.size)           // uncompressed size
        header.appendLE(UInt16(nameData.count))
        header.appendLE(UInt16(0))            // extra length
        header.append(nameData)
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: data)
        offset += UInt64(header.count + data.count)
        entries.append(entry)
    }

    public func finish() throws {
        defer { try? handle.close() }
        let directoryOffset = offset
        var directory = Data()
        for e in entries {
            directory.appendLE(UInt32(0x0201_4B50))
            directory.appendLE(UInt16(0x031E))    // made by: Unix, spec 3.0
            directory.appendLE(UInt16(20))
            directory.appendLE(UInt16(1 << 11))
            directory.appendLE(UInt16(0))
            directory.appendLE(e.dosTime)
            directory.appendLE(e.dosDate)
            directory.appendLE(e.crc)
            directory.appendLE(e.size)
            directory.appendLE(e.size)
            directory.appendLE(UInt16(e.name.count))
            directory.appendLE(UInt16(0))         // extra
            directory.appendLE(UInt16(0))         // comment
            directory.appendLE(UInt16(0))         // disk number
            directory.appendLE(UInt16(0))         // internal attributes
            directory.appendLE(UInt32(0o100644) << 16) // external: regular file, rw-r--r--
            directory.appendLE(e.offset)
            directory.append(e.name)
        }
        guard directoryOffset + UInt64(directory.count) < UInt64(UInt32.max), entries.count < Int(UInt16.max) else {
            throw ExportError.archiveTooLarge
        }
        var end = Data()
        end.appendLE(UInt32(0x0605_4B50))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt32(directory.count))
        end.appendLE(UInt32(directoryOffset))
        end.appendLE(UInt16(0))
        try handle.write(contentsOf: directory)
        try handle.write(contentsOf: end)
        try handle.synchronize()
    }

    static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year: Int = max(1980, min(2107, c.year ?? 1980))
        let hour: Int = c.hour ?? 0, minute: Int = c.minute ?? 0, second: Int = c.second ?? 0
        let month: Int = c.month ?? 1, day: Int = c.day ?? 1
        let time: Int = (hour << 11) | (minute << 5) | (second / 2)
        let date: Int = ((year - 1980) << 9) | (month << 5) | day
        return (UInt16(time), UInt16(date))
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
