import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError("goldeneye_native_swift_smoke: \(message)")
    }
}

let abiVersion = UInt32(GE_NATIVE_ABI_VERSION)
expect(MemoryLayout<GEAbiHeaderV1>.size == 8, "ABI header size")
expect(MemoryLayout<GEInitRequestV1>.size == 16, "init request size")
expect(MemoryLayout<GEInputSnapshotV1>.size == 32, "input snapshot size")
expect(MemoryLayout<GEVertexV1>.size == 20, "vertex size")
expect(MemoryLayout<GECommandWordsV1>.size == 8, "command size")
expect(MemoryLayout<GEFixturePacketV1>.size == 112, "fixture packet size")
expect(MemoryLayout<GEFixtureResultV1>.size == 128, "fixture result size")
expect(MemoryLayout<GEFrameResultV1>.size == 56, "frame result size")
expect(MemoryLayout<GEFixturePacketV1>.alignment == 8, "fixture packet alignment")

var request = GEInitRequestV1(
    header: GEAbiHeaderV1(abi_version: abiVersion, struct_size: UInt32(MemoryLayout<GEInitRequestV1>.size)),
    flags: 0,
    reserved: 0
)
expect(ge_native_initialize(request) == GE_STATUS_OK, "initialize")

var coldAndReadyPacket = ge_native_fixture_packet()
expect(coldAndReadyPacket.status == GE_STATUS_OK, "fixture packet status")
let firstPacket = coldAndReadyPacket.packet
expect(firstPacket.packet_hash != 0, "nonzero fixture hash")
expect(firstPacket.packet_version == UInt32(GE_NATIVE_PACKET_VERSION), "packet version")
expect(firstPacket.vertex_count == 3, "vertex count")
expect(firstPacket.command_count == 2, "command count")
expect(firstPacket.commands.0.w0 == 0xbf000000, "triangle opcode")
expect(firstPacket.commands.1.w0 == 0xb8000000, "end opcode")

let malformedVersion = GEInitRequestV1(
    header: GEAbiHeaderV1(abi_version: abiVersion + 1, struct_size: UInt32(MemoryLayout<GEInitRequestV1>.size)),
    flags: 0,
    reserved: 0
)
expect(ge_native_initialize(malformedVersion) == GE_STATUS_INVALID_VERSION, "invalid version")

request.header.struct_size -= 1
expect(ge_native_initialize(request) == GE_STATUS_INVALID_SIZE, "invalid size")
request.header.struct_size = UInt32(MemoryLayout<GEInitRequestV1>.size)
expect(ge_native_initialize(request) == GE_STATUS_INVALID_STATE, "duplicate initialize")

let input = GEInputSnapshotV1(
    header: GEAbiHeaderV1(abi_version: abiVersion, struct_size: UInt32(MemoryLayout<GEInputSnapshotV1>.size)),
    sequence: 1,
    held: 0x10,
    pressed: 0x10,
    released: 0,
    reserved: 0
)
let frame = ge_native_step(input)
expect(frame.status == GE_STATUS_OK, "step")
expect(frame.tick == 1, "tick")
expect(frame.packet_hash == firstPacket.packet_hash, "packet hash through step")
expect(frame.event_hash != 0, "event hash")

let secondPacket = ge_native_fixture_packet().packet
expect(secondPacket.packet_hash == firstPacket.packet_hash, "repeated packet hash")
expect(secondPacket.vertices.0.x == firstPacket.vertices.0.x, "immutable vertex x")
expect(secondPacket.vertices.2.a == 255, "vertex alpha")

expect(ge_native_shutdown() == GE_STATUS_OK, "shutdown")
expect(ge_native_shutdown() == GE_STATUS_INVALID_STATE, "repeated shutdown")

print("goldeneye_native_swift_smoke: PASS hash=\(firstPacket.packet_hash)")
