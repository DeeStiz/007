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

    static func loadTextureBlobsFromEnvironment() throws -> [GETextureSourceBlobV3] {
        let rootPath = ProcessInfo.processInfo.environment["GOLDENEYE_CLASSIC_TEXTURE_ROOT"]
            ?? "build/native/classic-textures"
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let definitions: [(UInt32, String)] = [
            (0x21, "AMMOCRATE1.bin"),
            (0x27, "AMMOTEXT765.bin"),
            (0x25, "CRATEROPE.bin"),
        ]
        return try definitions.map { textureID, filename in
            let url = rootURL.appendingPathComponent(filename)
            let data: Data
            do {
                data = try Data(contentsOf: url, options: [.mappedIfSafe])
            } catch {
                throw GoldenEyeClassicPropAssetError.unreadable(url, error)
            }
            guard !data.isEmpty,
                  data.count <= Int(GE_TEXTURE_SOURCE_BLOB_CAPACITY) else {
                throw GoldenEyeClassicPropAssetError.tooLarge(data.count)
            }
            var blob = GETextureSourceBlobV3()
            blob.header.abi_version = UInt32(GE_TEXTURE_REPLAY_ABI_VERSION)
            blob.header.struct_size = UInt32(MemoryLayout<GETextureSourceBlobV3>.size)
            blob.texture_id = textureID
            blob.byte_count = UInt32(data.count)
            blob.reserved = 0
            withUnsafeMutableBytes(of: &blob) { raw in
                let payloadOffset = MemoryLayout<GEAbiHeaderV1>.size + MemoryLayout<UInt32>.size * 3
                guard let destination = raw.baseAddress?.advanced(by: payloadOffset) else { return }
                data.withUnsafeBytes { source in
                    guard let sourceAddress = source.baseAddress else { return }
                    destination.copyMemory(from: sourceAddress, byteCount: data.count)
                }
            }
            return blob
        }
    }

    static func textureMaterials() -> GETextureMaterialSetV3 {
        var materials = GETextureMaterialSetV3()
        materials.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        materials.header.struct_size = UInt32(MemoryLayout<GETextureMaterialSetV3>.size)
        materials.material_count = UInt32(GE_TEXTURE_MATERIAL_CAPACITY)
        materials.reserved = 0
        let definitions: [(UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt64)] = [
            (0x21, 64, 32, 7, UInt32(GE_TEXTURE_FORMAT_I8), UInt32(GE_TEXTURE_COMPRESSION_HUFFMAN_BLUR), 0, 0x96c331f295054786),
            (0x27, 128, 16, 7, UInt32(GE_TEXTURE_FORMAT_IA4), UInt32(GE_TEXTURE_COMPRESSION_HUFFMAN_LOOKUP), 2, 0x0b91dd635318355a),
            (0x25, 32, 32, 6, UInt32(GE_TEXTURE_FORMAT_RGBA16_CI8), 0, 2, 0xbc68a84830d902be),
        ]
        withUnsafeMutableBytes(of: &materials.materials) { raw in
            let stride = MemoryLayout<GETextureMaterialDescriptorV3>.stride
            let typed = raw.bindMemory(to: GETextureMaterialDescriptorV3.self)
            for (index, definition) in definitions.enumerated() {
                let (textureID, width, height, mipmapTiles, format, compression, flags, sourceHash) = definition
                typed[index].texture_id = textureID
                typed[index].width = width
                typed[index].height = height
                typed[index].mipmap_tiles = mipmapTiles
                typed[index].format = format
                typed[index].compression = compression
                typed[index].s_flags = flags
                typed[index].t_flags = flags
                typed[index].source_byte_count = [1610, 551, 1003][index]
                typed[index].source_hash = sourceHash
                _ = stride
            }
        }
        return materials
    }
}
