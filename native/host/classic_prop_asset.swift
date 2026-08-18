import Foundation
import GoldenEyeNative

enum GoldenEyeClassicPropAssetError: Error, CustomStringConvertible {
    case missingEnvironment
    case unreadable(URL, Error)
    case tooLarge(Int)
    case empty(URL)

    var description: String {
        switch self {
        case .missingEnvironment:
            return "GOLDENEYE_CLASSIC_PROP_ASSET is not set"
        case .unreadable(let url, let error):
            return "cannot read classic prop asset at \(url.path): \(error)"
        case .tooLarge(let count):
            return "classic prop asset is \(count) bytes; capacity is \(GE_CLASSIC_ASSET_BLOB_CAPACITY)"
        case .empty(let url):
            return "classic prop asset is empty: \(url.path)"
        }
    }
}

enum GoldenEyeClassicPropAsset {
    static func loadFromEnvironment() throws -> GEClassicAssetBlobV2 {
        guard let path = ProcessInfo.processInfo.environment["GOLDENEYE_CLASSIC_PROP_ASSET"],
              !path.isEmpty else {
            throw GoldenEyeClassicPropAssetError.missingEnvironment
        }
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw GoldenEyeClassicPropAssetError.unreadable(url, error)
        }
        guard !data.isEmpty else {
            throw GoldenEyeClassicPropAssetError.empty(url)
        }
        guard data.count <= Int(GE_CLASSIC_ASSET_BLOB_CAPACITY) else {
            throw GoldenEyeClassicPropAssetError.tooLarge(data.count)
        }

        var blob = GEClassicAssetBlobV2()
        blob.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        blob.header.struct_size = UInt32(MemoryLayout<GEClassicAssetBlobV2>.size)
        blob.byte_count = UInt32(data.count)
        blob.reserved = 0

        withUnsafeMutableBytes(of: &blob) { raw in
            let payloadOffset = MemoryLayout<GEAbiHeaderV1>.size + MemoryLayout<UInt32>.size * 2
            guard let destination = raw.baseAddress?.advanced(by: payloadOffset) else { return }
            data.withUnsafeBytes { source in
                guard let sourceAddress = source.baseAddress else { return }
                destination.copyMemory(from: sourceAddress, byteCount: data.count)
            }
        }
        return blob
    }
}
