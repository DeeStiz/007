import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Swift-side value-only adapter for the directly compiled guard/door owner.
/// It performs no selection, animation, AI, or door decisions.  Those remain
/// in the C owner; this type only copies bounded pages into the existing
/// GERamRomGameplay V6 ABI and verifies that no source identity was lost.
public enum GoldenEyeGuardDoorOwnerV6Adapter {
    public enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case status(UInt32, String)
        case invalidPage(String)

        public var description: String {
            switch self {
            case let .status(status, operation):
                return "guard/door owner " + operation + " failed with status " + String(status)
            case let .invalidPage(field):
                return "guard/door owner page is invalid: " + field
            }
        }
    }

    public struct GameplayPages: Sendable {
        public let entities: [GERamRomGameplayEntityV6]
        public let attachments: [GERamRomGameplayAttachmentV6]
    }

    public static func assertLayouts() {
        precondition(MemoryLayout<GEGuardDoorOwnerSetupV6>.size == 88)
        precondition(MemoryLayout<GEGuardDoorOwnerGuardSourceV6>.size == 1920)
        precondition(MemoryLayout<GEGuardDoorOwnerDoorSourceV6>.size == 240)
        precondition(MemoryLayout<GEGuardDoorOwnerGuardStateV6>.size == 15024)
        precondition(MemoryLayout<GEGuardDoorOwnerDoorStateV6>.size == 384)
        precondition(MemoryLayout<GEGuardDoorOwnerStateV6>.size == 1_972_424)
        precondition(MemoryLayout<GEGuardDoorOwnerEventV6>.size == 120)
    }

    /// Copy the source owner state into the existing gameplay page contract.
    /// The C function bounds every copy; Swift additionally validates every
    /// copied record before returning it to the stage owner.
    public static func gameplayPages(
        from state: inout GEGuardDoorOwnerStateV6
    ) throws -> GameplayPages {
        let entityCapacity = Int(state.guard_count + state.door_count)
        let attachmentCapacity = Int(state.attachment_count)
        var entities = [GERamRomGameplayEntityV6](
            repeating: GERamRomGameplayEntityV6(), count: max(1, entityCapacity)
        )
        var gameplayAttachments = [GERamRomGameplayAttachmentV6](
            repeating: GERamRomGameplayAttachmentV6(), count: max(1, attachmentCapacity)
        )
        var copiedEntities: UInt32 = 0
        var copiedAttachments: UInt32 = 0
        let status: UInt32 = entities.withUnsafeMutableBufferPointer { entityBuffer in
            gameplayAttachments.withUnsafeMutableBufferPointer { attachmentBuffer in
                ge_guard_door_owner_v6_copy_gameplay_pages(
                    &state,
                    UInt32(entityCapacity), entityBuffer.baseAddress,
                    UInt32(attachmentCapacity), attachmentBuffer.baseAddress,
                    &copiedEntities, &copiedAttachments
                )
            }
        }
        guard status == UInt32(GE_STATUS_OK) else {
            throw Error.status(status, "copy_gameplay_pages")
        }
        guard copiedEntities == UInt32(entityCapacity),
              copiedAttachments == UInt32(attachmentCapacity) else {
            throw Error.invalidPage("copy counts")
        }
        for index in 0..<Int(copiedEntities) {
            var entity = entities[index]
            guard ge_ramrom_gameplay_v6_validate_entity(&entity) == GE_STATUS_OK else {
                throw Error.invalidPage("entity[\(index)]")
            }
            entities[index] = entity
        }
        for index in 0..<Int(copiedAttachments) {
            var attachment = gameplayAttachments[index]
            guard ge_ramrom_gameplay_v6_validate_attachment(&attachment) == GE_STATUS_OK else {
                throw Error.invalidPage("attachment[\(index)]")
            }
            gameplayAttachments[index] = attachment
        }
        return GameplayPages(
            entities: Array(entities.prefix(Int(copiedEntities))),
            attachments: Array(gameplayAttachments.prefix(Int(copiedAttachments)))
        )
    }

    /// Parse the source ModelAnimation header from a prepared animationtable
    /// payload.  The payload is borrowed only for this call and must already
    /// have passed its catalog hash/digest guard.  This helper intentionally
    /// returns only source frame metadata; pose rows still have to be supplied
    /// by the directly compiled animation producer.
    public static func animationHeader(
        from preparedPayload: Data,
        offset: Int
    ) throws -> (frameCount: UInt32, loop: Bool, sourceHash: UInt64) {
        guard offset >= 0, offset <= preparedPayload.count, preparedPayload.count - offset >= 8 else {
            throw Error.invalidPage("animation header bounds")
        }
        let frameCount = UInt32(preparedPayload[offset + 4]) << 8 |
            UInt32(preparedPayload[offset + 5])
        let loop = (preparedPayload[offset + 7] & 1) != 0
        guard frameCount > 0, frameCount <= 4096 else {
            throw Error.invalidPage("animation frame count")
        }
        var hash: UInt64 = 1469598103934665603
        for byte in preparedPayload {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        guard hash != 0 else { throw Error.invalidPage("animation source hash") }
        return (frameCount, loop, hash)
    }

    /// The existing source animation pose ABI is the canonical joint page for
    /// this owner.  This check is intentionally strict: an empty page or a
    /// T-pose/identity-only page cannot be promoted to a visible guard.
    public static func validatePosePage(
        _ poses: [GESourceAnimationPoseV6],
        skeletonHandle: UInt32,
        frameCount: UInt32
    ) throws {
        guard !poses.isEmpty, poses.count <= Int(GE_GUARD_DOOR_OWNER_V6_MAX_POSES_PER_GUARD) else {
            throw Error.invalidPage("pose count")
        }
        var nonIdentity = false
        for poseValue in poses {
            var pose = poseValue
            guard pose.skeleton_handle == skeletonHandle,
                  pose.node_handle != 0,
                  pose.animation_tick < frameCount,
                  pose.pose_hash != 0,
                  ge_source_scene_v6_validate_animation_pose(&pose) == GE_STATUS_OK else {
                throw Error.invalidPage("pose identity")
            }
            if pose.translation_q16.0 != 0 || pose.translation_q16.1 != 0 || pose.translation_q16.2 != 0 ||
                pose.rotation_q16.0 != 0 || pose.rotation_q16.1 != 0 || pose.rotation_q16.2 != 0 ||
                pose.scale_q16.0 != 65_536 || pose.scale_q16.1 != 65_536 || pose.scale_q16.2 != 65_536 {
                nonIdentity = true
            }
        }
        guard nonIdentity else { throw Error.invalidPage("identity-only pose page") }
    }
}
