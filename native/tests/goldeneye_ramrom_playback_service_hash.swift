import Foundation

// Standalone service smoke helper. The product target receives this value
// type from goldeneye_boot_flow.swift; the focused smoke intentionally avoids
// pulling the full AppKit/Metal title owner into its compile.
enum GoldenEyeTitleHash {
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
