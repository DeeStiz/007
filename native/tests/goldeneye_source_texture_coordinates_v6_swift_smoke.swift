import Foundation

let texture = GE_SOURCE_TEXTURE_COORDINATES_V6_OP_TEXTURE
let setTile = GE_SOURCE_TEXTURE_COORDINATES_V6_OP_SETTILE
let setTileSize = GE_SOURCE_TEXTURE_COORDINATES_V6_OP_SETTILESIZE

func tileW0(_ opcode: UInt32, format: UInt32 = 0, size: UInt32 = 2) -> UInt32 {
    opcode << 24 | format << 21 | size << 19 | 8 << 9
}

func tileW1(
    tile: UInt32 = 0,
    cmt: UInt32 = GE_SOURCE_TEXTURE_COORDINATES_V6_ADDRESS_CLAMP,
    cms: UInt32 = GE_SOURCE_TEXTURE_COORDINATES_V6_ADDRESS_CLAMP
) -> UInt32 {
    tile << 24 | cmt << 18 | cms << 8
}

func tileSizeW0(_ uls: UInt32 = 0, _ ult: UInt32 = 0) -> UInt32 {
    setTileSize << 24 | uls << 12 | ult
}

func tileSizeW1(_ lrs: UInt32, _ lrt: UInt32, tile: UInt32 = 0) -> UInt32 {
    tile << 24 | lrs << 12 | lrt
}

@main
struct GoldenEyeSourceTextureCoordinatesV6Smoke {
    static func main() throws {
        let input = GoldenEyeSourceTextureCoordinateV6.input(
            sourceCommandOffset: 0x120,
            sourceVertexIndex: 7,
            textureHandle: 0x7001,
            sourceS10_5: 0x400,
            sourceT10_5: 0x400,
            textureCommandW0: texture << 24 | 1,
            textureCommandW1: 0xffff_ffff,
            tileCommandW0: tileW0(setTile),
            tileCommandW1: tileW1(),
            tileSizeCommandW0: tileSizeW0(),
            tileSizeCommandW1: tileSizeW1(31 * 4, 31 * 4),
            maxLevel: 0,
            levelCount: 1,
            levelWidth: 32,
            levelHeight: 32,
            flags: GE_SOURCE_TEXTURE_COORDINATES_V6_FLAG_SOURCE_ANCHOR,
            sourceStateHash: 0x0102_0304_0506_0708,
            sourceCommandHash: 0x1112_1314_1516_1718
        )

        precondition(MemoryLayout<GETextureCoordinateInputV6>.size == 104)
        precondition(MemoryLayout<GETextureCoordinateResultV6>.size == 264)
        let lowered = try GoldenEyeSourceTextureCoordinateV6.lower(input)
        precondition(lowered.result.source_s10_5 == 0x400)
        precondition(lowered.result.scaled_s_q16 == Int64(32) * 65_536 - 32)
        precondition(lowered.result.normalized_s_q16 == 63_488)
        precondition(lowered.sourceLink.commandOffset == 0x120)
        precondition(lowered.sourceLink.vertexIndex == 7)
        precondition(lowered.sourceLink.textureHandle == 0x7001)
        precondition(lowered.coordinateHash != 0)
        print("goldeneye_source_texture_coordinates_v6_swift_smoke: PASS hash=\(lowered.coordinateHash)")
    }
}
