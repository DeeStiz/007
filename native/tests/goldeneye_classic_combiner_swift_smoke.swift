import Foundation

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

let propPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "build/native/classic-prop/Pammo_crate1Z.bin"
let propData = try Data(contentsOf: URL(fileURLWithPath: propPath))
expect(propData.count == 1488, "ammo crate payload size")

var propBlob = GEClassicAssetBlobV2()
propBlob.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
propBlob.header.struct_size = UInt32(MemoryLayout<GEClassicAssetBlobV2>.size)
propBlob.byte_count = UInt32(propData.count)
propBlob.reserved = 0
withUnsafeMutableBytes(of: &propBlob) { destination in
    let payloadOffset = MemoryLayout<GEAbiHeaderV1>.size + MemoryLayout<UInt32>.size * 2
    propData.withUnsafeBytes { source in
        guard let sourceAddress = source.baseAddress else { return }
        destination.baseAddress!.advanced(by: payloadOffset)
            .copyMemory(from: sourceAddress, byteCount: propData.count)
    }
}

expect(MemoryLayout<GEClassicCombinerCommandV4>.size == 8,
       "V4 command layout")
expect(MemoryLayout<GEClassicCombinerStateV4>.size == 80,
       "V4 combiner layout")
expect(MemoryLayout<GEClassicOtherModeV4>.size == 64,
       "V4 other-mode layout")
expect(MemoryLayout<GEClassicRenderModeV4>.size == 80,
       "V4 render-mode layout")
expect(MemoryLayout<GEClassicCombinerDrawKeyV4>.size == 264,
       "V4 draw-key layout")
expect(MemoryLayout<GEClassicCombinerLoweringResultV4>.size == 1400,
       "V4 result layout")

let first = ge_classic_lower_ammo_crate_v4(propBlob)
let second = ge_classic_lower_ammo_crate_v4(propBlob)
expect(first.status == GE_STATUS_OK, "V4 lowering status")
expect(first.header.abi_version == GE_NATIVE_ABI_VERSION, "V4 ABI version")
expect(first.header.struct_size == UInt32(MemoryLayout<GEClassicCombinerLoweringResultV4>.size),
       "V4 result struct size")
expect(first.commands_processed == 22, "V4 prop command count")
expect(first.setup_commands_processed == 3, "V4 setup command count")
expect(first.draw_count == 4, "V4 draw count")
expect(first.setup_hash != 0 && first.event_hash != 0 && first.key_hash != 0,
       "V4 hashes")
expect(first.setup_hash == second.setup_hash && first.event_hash == second.event_hash &&
       first.key_hash == second.key_hash, "V4 deterministic hashes")

let expectedOffsets: [UInt32] = [0x50, 0x68, 0x90, 0xb0]
let expectedTextures: [UInt32] = [0x21, 0x21, 0x27, 0x25]
let expectedModes: [UInt32] = [0xc4112078, 0xc4112078, 0xc4104dd8, 0xc4104dd8]
let drawKeys: [GEClassicCombinerDrawKeyV4] = withUnsafeBytes(of: first.draws) { rawBytes in
    Array(rawBytes.bindMemory(to: GEClassicCombinerDrawKeyV4.self))
}
for index in 0..<4 {
    let draw = drawKeys[index]
    expect(draw.header.abi_version == GE_NATIVE_ABI_VERSION,
           "V4 draw ABI version")
    expect(draw.header.struct_size == UInt32(MemoryLayout<GEClassicCombinerDrawKeyV4>.size),
           "V4 draw struct size")
    expect(draw.source_command_offset == expectedOffsets[index],
           "V4 source command offset")
    expect(draw.texture_id == expectedTextures[index], "V4 texture sequence")
    expect(draw.combiner.raw_w0 == 0xfc26a004 && draw.combiner.raw_w1 == 0x1f1093ff,
           "V4 ModelType-4 combiner words")
    expect(draw.render_mode.raw_mode == expectedModes[index],
           "V4 render-mode sequence")
    expect(draw.key_hash != 0, "V4 draw key hash")
}

var malformedInput = ge_classic_ammo_crate_combiner_input_v4(propBlob)
malformedInput.setup_command_count = 0
expect(ge_classic_lower_combiner_v4(malformedInput).status != GE_STATUS_OK,
       "V4 malformed setup rejection")
var malformedBlob = propBlob
malformedBlob.header.abi_version += 1
expect(ge_classic_lower_ammo_crate_v4(malformedBlob).status == GE_STATUS_INVALID_VERSION,
       "V4 malformed blob rejection")

// Frozen V1 regression.
var request = GEInitRequestV1()
request.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
request.header.struct_size = UInt32(MemoryLayout<GEInitRequestV1>.size)
expect(ge_native_initialize(request) == GE_STATUS_OK, "V1 initialize")
let v1 = ge_native_fixture_packet()
expect(v1.status == GE_STATUS_OK && v1.packet.packet_hash == 1522029846112142469,
       "V1 frozen hash")
expect(ge_native_shutdown() == GE_STATUS_OK, "V1 shutdown")

// Frozen V2 regression.
let v2 = ge_classic_replay_fixture(ge_classic_nested_fixture())
expect(v2.status == GE_STATUS_OK, "V2 status")
expect(v2.packet_hash == 65363635960931316 &&
       v2.event_hash == 905714786767796339 &&
       v2.state_hash == 10439205544326414085, "V2 frozen hashes")

// Frozen V3 regression.  The V4 sidecar must not change this record or any
// of its source/material hashes.
var materials = GETextureMaterialSetV3()
materials.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
materials.header.struct_size = UInt32(MemoryLayout<GETextureMaterialSetV3>.size)
materials.material_count = UInt32(GE_TEXTURE_MATERIAL_CAPACITY)
withUnsafeMutableBytes(of: &materials.materials) { raw in
    let records = raw.bindMemory(to: GETextureMaterialDescriptorV3.self)
    records[0].texture_id = 0x21
    records[0].width = 64
    records[0].height = 32
    records[0].mipmap_tiles = 7
    records[0].format = UInt32(GE_TEXTURE_FORMAT_I8)
    records[0].compression = UInt32(GE_TEXTURE_COMPRESSION_HUFFMAN_BLUR)
    records[0].source_byte_count = 1610
    records[0].source_hash = 0x96c331f295054786
    records[1].texture_id = 0x27
    records[1].width = 128
    records[1].height = 16
    records[1].mipmap_tiles = 7
    records[1].format = UInt32(GE_TEXTURE_FORMAT_IA4)
    records[1].compression = UInt32(GE_TEXTURE_COMPRESSION_HUFFMAN_LOOKUP)
    records[1].s_flags = 2
    records[1].t_flags = 2
    records[1].source_byte_count = 551
    records[1].source_hash = 0x0b91dd635318355a
    records[2].texture_id = 0x25
    records[2].width = 32
    records[2].height = 32
    records[2].mipmap_tiles = 6
    records[2].format = UInt32(GE_TEXTURE_FORMAT_RGBA16_CI8)
    records[2].s_flags = 2
    records[2].t_flags = 2
    records[2].source_byte_count = 1003
    records[2].source_hash = 0xbc68a84830d902be
}
let v3 = ge_classic_replay_textured_prop_v3(propBlob, materials)
expect(v3.status == GE_STATUS_OK, "V3 status")
expect(v3.packet_hash == 11580554792388204033 &&
       v3.event_hash == 9845751795158270468 &&
       v3.material_hash == 14168780479827987350, "V3 frozen hashes")

print("goldeneye_classic_combiner_swift_smoke: PASS " +
      "v1=\(v1.packet.packet_hash) " +
      "v2Packet=\(v2.packet_hash) v2Event=\(v2.event_hash) v2State=\(v2.state_hash) " +
      "v3Packet=\(v3.packet_hash) v3Event=\(v3.event_hash) v3Material=\(v3.material_hash) " +
      "packetHash=\(v3.packet_hash) eventHash=\(v3.event_hash) materialHash=\(v3.material_hash) " +
      "v4Setup=\(first.setup_hash) v4Event=\(first.event_hash) v4Key=\(first.key_hash)")
