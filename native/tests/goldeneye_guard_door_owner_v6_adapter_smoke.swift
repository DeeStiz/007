import Foundation

@main
struct GoldenEyeGuardDoorOwnerV6AdapterSmoke {
    static func main() throws {
        GoldenEyeGuardDoorOwnerV6Adapter.assertLayouts()
        guard CommandLine.arguments.count == 2 else {
            fatalError("usage: guard_door_owner_adapter_smoke animationtable-data")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: [.mappedIfSafe])
        let header = try GoldenEyeGuardDoorOwnerV6Adapter.animationHeader(from: data, offset: 0x4018)
        precondition(header.frameCount == 37)
        precondition(header.loop)

        var pose = GESourceAnimationPoseV6()
        pose.header.abi_version = GE_NATIVE_ABI_VERSION
        pose.header.struct_size = UInt32(MemoryLayout<GESourceAnimationPoseV6>.size)
        pose.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        pose.pose_handle = 0xD700_0001
        pose.skeleton_handle = 0x1001
        pose.node_handle = 1
        pose.flags = UInt32(GE_SOURCE_POSE_V6_FLAG_INTERPOLATABLE)
        pose.animation_tick = 1
        pose.translation_q16 = (1024, 8192, 512)
        pose.rotation_q16 = (0, 2048, 0, 65_536)
        pose.scale_q16 = (65_536, 65_536, 65_536)
        pose.pose_hash = header.sourceHash ^ 1
        try GoldenEyeGuardDoorOwnerV6Adapter.validatePosePage(
            [pose], skeletonHandle: 0x1001, frameCount: header.frameCount
        )

        var state = GEGuardDoorOwnerStateV6()
        state.header.abi_version = GE_NATIVE_ABI_VERSION
        state.header.struct_size = UInt32(MemoryLayout<GEGuardDoorOwnerStateV6>.size)
        state.record_version = UInt32(GE_GUARD_DOOR_OWNER_V6_RECORD_VERSION)
        let pages = try GoldenEyeGuardDoorOwnerV6Adapter.gameplayPages(from: &state)
        precondition(pages.entities.isEmpty && pages.attachments.isEmpty)
        print("goldeneye_guard_door_owner_v6_adapter_smoke: PASS animationFrameCount=\(header.frameCount) sourceHash=\(header.sourceHash) zeroPages=1 pose=1")
    }
}
