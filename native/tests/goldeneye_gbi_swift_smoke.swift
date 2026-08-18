let stream = ge_native_gbi_fixture_stream()
let first = ge_native_normalize_gbi(stream)
let second = ge_native_normalize_gbi(stream)
precondition(first.status == GE_STATUS_OK)
precondition(first.packet.vertex_count == 3)
precondition(first.packet.command_count == 2)
precondition(first.packet.commands.0.w0 == 0xbf000000)
precondition(first.packet.commands.1.w0 == 0xb8000000)
precondition(first.packet_hash == second.packet_hash)
precondition(first.event_hash == second.event_hash)
precondition(first.packet.packet_hash == first.packet_hash)

var malformed = stream
malformed.header.abi_version += 1
precondition(ge_native_normalize_gbi(malformed).status == GE_STATUS_INVALID_VERSION)
malformed = stream
malformed.commands.1.w0 = 0x99000000
let unsupported = ge_native_normalize_gbi(malformed)
precondition(unsupported.status == GE_STATUS_UNSUPPORTED_COMMAND)
precondition(unsupported.error_opcode == 0x99)
precondition(unsupported.error_offset == 8)

malformed = stream
malformed.resources.first_vertex = UInt32.max
precondition(ge_native_normalize_gbi(malformed).status == GE_STATUS_MALFORMED_STREAM)

print("goldeneye_gbi_swift_smoke: PASS hash=\(first.packet_hash)")
