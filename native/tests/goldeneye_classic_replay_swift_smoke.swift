let fixture = ge_classic_nested_fixture()
precondition(fixture.header.abi_version == GE_NATIVE_ABI_VERSION)
precondition(fixture.header.struct_size == UInt32(MemoryLayout<GEClassicReplayFixtureV2>.size))
precondition(fixture.packet_version == GE_CLASSIC_REPLAY_PACKET_VERSION)
precondition(fixture.command_count > 0)
precondition(fixture.list_count > 0)

let first = ge_classic_replay_fixture(fixture)
let second = ge_classic_replay_fixture(fixture)
precondition(first.status == GE_STATUS_OK)
precondition(first.draw_count > 0)
precondition(first.vertex_count > 0)
precondition(first.triangle_count > 0)
precondition(first.packet_hash != 0)
precondition(first.event_hash != 0)
precondition(first.state_hash != 0)
precondition(first.packet_hash == second.packet_hash)
precondition(first.event_hash == second.event_hash)
precondition(first.state_hash == second.state_hash)
precondition(first.draw_count == second.draw_count)
precondition(first.vertex_count == second.vertex_count)
precondition(first.triangle_count == second.triangle_count)

var malformed = fixture
malformed.header.abi_version += 1
precondition(ge_classic_replay_fixture(malformed).status == GE_STATUS_INVALID_VERSION)

malformed = fixture
malformed.command_count = 0
precondition(ge_classic_replay_fixture(malformed).status == GE_STATUS_MALFORMED_STREAM)

print("goldeneye_classic_replay_swift_smoke: PASS commands=\(first.commands_processed) draws=\(first.draw_count) triangles=\(first.triangle_count) packetHash=\(first.packet_hash) eventHash=\(first.event_hash) stateHash=\(first.state_hash)")
