import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

expect(MemoryLayout<GETextureSourceBlobV3>.size == 4116,
       "texture source blob layout")
expect(MemoryLayout<GETextureMaterialDescriptorV3>.size == 48,
       "texture descriptor layout")
expect(MemoryLayout<GETextureMaterialSetV3>.size == 160,
       "texture material set layout")
expect(MemoryLayout<GETextureDecodeResultV3>.size == 17560,
       "texture decode result layout")
expect(MemoryLayout<GETextureMaterialStateV3>.size == 56,
       "texture material state layout")
expect(MemoryLayout<GETexturedVertexV3>.size == 32,
       "textured vertex layout")
expect(MemoryLayout<GETexturedDrawPacketV3>.size == 1552,
       "textured draw layout")
expect(MemoryLayout<GETexturedReplayResultV3>.size == 12488,
       "textured replay result layout")

let request = GEInitRequestV1(
    header: GEAbiHeaderV1(
        abi_version: GE_NATIVE_ABI_VERSION,
        struct_size: UInt32(MemoryLayout<GEInitRequestV1>.size)
    ),
    flags: 0,
    reserved: 0
)
expect(ge_native_initialize(request) == GE_STATUS_OK, "V1 initialize")
let readyNativeFixture = ge_native_fixture_packet()
expect(readyNativeFixture.status == GE_STATUS_OK, "V1 fixture status")
expect(readyNativeFixture.packet.packet_hash == 1522029846112142469,
       "V1 fixture regression hash")
expect(ge_native_shutdown() == GE_STATUS_OK, "V1 shutdown")

let classicFixture = ge_classic_nested_fixture()
let classic = ge_classic_replay_fixture(classicFixture)
expect(classic.status == GE_STATUS_OK, "V2 fixture status")
expect(classic.packet_hash == 65363635960931316,
       "V2 packet regression hash")
expect(classic.event_hash == 905714786767796339,
       "V2 event regression hash")
expect(classic.state_hash == 10439205544326414085,
       "V2 state regression hash")

print("goldeneye_texture_replay_swift_smoke: PASS " +
      "v1=\(readyNativeFixture.packet.packet_hash) " +
      "v2Packet=\(classic.packet_hash) " +
      "v2Event=\(classic.event_hash) " +
      "v2State=\(classic.state_hash)")
