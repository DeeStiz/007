import Foundation

/// Canonical little-endian FNV-1a used by the source attract route's copied
/// catalog. Kept in its own host file so the cast composer remains isolated
/// from route-table implementation edits.
enum GoldenEyeCastRouteHash {
    static func fnv1a(_ words: [UInt64]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for word in words {
            var value = word.littleEndian
            withUnsafeBytes(of: &value) { bytes in
                for byte in bytes {
                    hash ^= UInt64(byte)
                    hash &*= 0x100000001b3
                }
            }
        }
        return hash
    }
}
