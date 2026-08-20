import CryptoKit
import Foundation

/// Immutable source-language catalog for the frontend text asset. The file is
/// a big-endian offset table followed by NUL-terminated strings. The catalog
/// stores copied Swift strings and a source digest; it never retains a ROM
/// buffer, segmented address, or host pointer.
struct GoldenEyeTitleTextCatalog: Sendable, Equatable {
    enum Error: Swift.Error, CustomStringConvertible {
        case missing(URL)
        case truncated
        case invalid(String)

        var description: String {
            switch self {
            case .missing(let url): return "title text asset is missing: \(url.path)"
            case .truncated: return "title text asset is truncated"
            case .invalid(let detail): return "title text asset is invalid: \(detail)"
            }
        }
    }

    let strings: [String]
    let sourceSHA256: String

    static func load(assetRoot: URL) throws -> Self {
        let url = assetRoot
            .appendingPathComponent("title", isDirectory: true)
            .appendingPathComponent("LtitleE.bin", isDirectory: false)
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw Error.missing(url)
        }
        guard data.count >= 4 else { throw Error.truncated }
        let firstOffset = Int(readBE32(data, at: 0))
        guard firstOffset >= 4, firstOffset <= data.count, firstOffset % 4 == 0 else {
            throw Error.invalid("first string offset \(firstOffset)")
        }
        var offsets: [Int] = []
        offsets.reserveCapacity(firstOffset / 4)
        var previous = firstOffset
        for index in 0..<(firstOffset / 4) {
            let offset = Int(readBE32(data, at: index * 4))
            if offset == 0 {
                break
            }
            guard offset >= firstOffset, offset <= data.count, offset >= previous else {
                throw Error.invalid("offset \(index)=\(offset) is not monotonic")
            }
            offsets.append(offset)
            previous = offset
        }
        let count = offsets.count
        guard count > 0, count <= 4096 else {
            throw Error.invalid("offset count \(count)")
        }

        var strings: [String] = []
        strings.reserveCapacity(count)
        for index in 0..<count {
            let start = offsets[index]
            let end = index + 1 < count ? offsets[index + 1] : data.count
            guard end >= start else { throw Error.invalid("string range \(index)") }
            let bytes = data[start..<end]
            let nul = bytes.firstIndex(of: 0) ?? bytes.endIndex
            let text = String(decoding: bytes[..<nul], as: UTF8.self)
                .trimmingCharacters(in: .newlines)
            strings.append(text)
        }

        let required = [
            "START", "NEXT", "PREVIOUS", "TWYCROSS BOARD OF GAME CLASSIFICATION",
            "Copy", "Erase", "SELECT MISSION", "MULTIPLAYER"
        ]
        for value in required where !strings.contains(value) {
            throw Error.invalid("required string is missing: \(value)")
        }
        return Self(
            strings: strings,
            sourceSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    static func fromEnvironment() -> Result<Self, Error> {
        guard let value = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_ASSET_ROOT"],
              !value.isEmpty else {
            return .failure(.invalid("GOLDENEYE_NATIVE_ASSET_ROOT is not set"))
        }
        do {
            return .success(try load(assetRoot: URL(fileURLWithPath: value, isDirectory: true)))
        } catch {
            return .failure(.invalid(String(describing: error)))
        }
    }

    func string(at index: Int) -> String? {
        guard strings.indices.contains(index) else { return nil }
        return strings[index]
    }

    private static func readBE32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }
}
