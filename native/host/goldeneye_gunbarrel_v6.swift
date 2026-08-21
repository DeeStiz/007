import CryptoKit
import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Source-owned Gunbarrel constants and prepared-resource evidence.
///
/// This is an additive host-side contract.  It does not replace title.c's
/// GBI producer and it deliberately refuses to describe the scene as
/// capture-ready while any prepared model packet still contains unsupported
/// source commands or while the encrypted blood payload is absent.
public struct GoldenEyeGunbarrelSourceManifestV6: Sendable, Equatable {
    public enum PartRole: UInt32, Sendable, Equatable {
        case body = 1
        case head = 2
        case weapon = 3
    }

    public struct Model: Sendable, Equatable {
        public let role: PartRole
        public let modelHandle: UInt32
        public let name: String
        public let sourceSHA256: String
        public let packetSHA256: String
        public let sourceLength: UInt32
        public let commandCount: UInt32
        public let unsupportedCommandCount: UInt32
        public let vertexCount: UInt32
        public let indexCount: UInt32

        public var complete: Bool { unsupportedCommandCount == 0 }
    }

    public struct Background: Sendable, Equatable {
        public let width: UInt32
        public let height: UInt32
        public let encodedByteCount: UInt32
        public let encodedSHA256: String

        public var complete: Bool { width == 440 && height == 299 && encodedByteCount > 10 }
    }

    public struct Blood: Sendable, Equatable {
        public let sourceSHA256: String
        public let encodedSHA256: String
        public let encodedByteCount: UInt32
        public let sourceWidth: UInt32
        public let sourceHeight: UInt32
        public let textureWidth: UInt32
        public let textureHeight: UInt32
        public let encodedPayloadAvailable: Bool

        public var complete: Bool {
            encodedPayloadAvailable && sourceWidth == 80 && sourceHeight == 96
                && textureWidth == 96 && textureHeight == 80
        }
    }

    public struct Animation: Sendable, Equatable {
        public let walkEntryOffset: UInt32
        public let fireEntryOffset: UInt32
        public let initialPlaySpeedQ16: UInt32
        public let fireStartFrameQ16: UInt32
        public let firePlaySpeedQ16: UInt32
        public let fireSpeedupQ16: UInt32
        public let animationStartSubstep: UInt32
        public let animationSpeedupSubstep: UInt32
        public let rifleCueSubstep: UInt32
    }

    public struct Attachment: Sendable, Equatable {
        public let gunParentSwitch: UInt32
        public let muzzleFlashSwitch: UInt32
        public let muzzleLightSwitch: UInt32
        public let bodyModelHandle: UInt32
        public let headModelHandle: UInt32
        public let weaponModelHandle: UInt32
    }

    public struct Camera: Sendable, Equatable {
        public let eyeQ16: SIMD3<Int32>
        public let directionQ16: SIMD3<Int32>
        public let upQ16: SIMD3<Int32>
        public let fovDegreesQ16: UInt32
        public let aspectNumerator: UInt32
        public let aspectDenominator: UInt32
        public let nearQ16: UInt32
        public let farQ16: UInt32
    }

    public let models: [Model]
    public let background: Background
    public let blood: Blood
    public let animation: Animation
    public let attachment: Attachment
    public let camera: Camera
    public let holeVertexCount: UInt32
    public let holeTriangleCount: UInt32
    public let sourceTitleSHA256: String
    public let sourceTitle3SHA256: String
    public let sourceBloodDecryptSHA256: String
    public let manifestHash: UInt64

    public var modelTraversalComplete: Bool {
        models.count == 3 && models.allSatisfy(\.complete)
    }

    public var captureReady: Bool {
        modelTraversalComplete && background.complete && blood.complete
    }

    public enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case invalidRoot(String)
        case missingAsset(String)
        case invalidAsset(String)
        case packet(String)

        public var description: String {
            switch self {
            case .invalidRoot(let value): return "gunbarrel root invalid: \(value)"
            case .missingAsset(let value): return "gunbarrel asset missing: \(value)"
            case .invalidAsset(let value): return "gunbarrel asset invalid: \(value)"
            case .packet(let value): return "gunbarrel packet invalid: \(value)"
            }
        }
    }

    private static let expectedSourceHashes: [UInt32: String] = [
        7: "b92a505abb9bd53e0d9b031835b8ebf5c32b4a308cbf80f08ba3be3b3084348e",
        8: "76a8e4e3d7baad79640262da2632b367147c5594a559ebfc55df829ef9214b88",
        9: "9870735843375db88871898c65c65ac54c00fc7e1d005be4f1ff4d8e6b26faa5"
    ]

    private static let expectedSourceTitleSHA256 =
        "1bdd78363b3ac05bc1b1148edcc17f577d3a81115faab530be0cd019c6261adc"
    private static let expectedSourceTitle3SHA256 =
        "5904bd61b9aaa87de976d0975b90f6df553324167f75108bd834bab740b5754f"
    private static let expectedSourceBloodSHA256 =
        "8d474a713b2c53fa3daa62999d440d12294d984d5dfa8a16830df521d5f7efe6"
    private static let expectedBloodEncodedSHA256 =
        "cc960835635ee32b1ef793e6c30f9ec8ed199cd416c5dd8d418db1307ed2dda2"

    /// Loads only prepared files beneath the explicitly supplied root.  The
    /// root may be either boot-assets (with a title/ directory) or the title
    /// directory itself.  No source checkout path and no ROM path is opened.
    public static func load(preparedRoot root: URL) throws -> Self {
        guard root.isFileURL, root.path.hasPrefix("/") else {
            throw Error.invalidRoot("absolute file URL required")
        }
        let standardized = root.standardizedFileURL
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &directory),
              directory.boolValue else {
            throw Error.invalidRoot(standardized.path)
        }
        let titleRoot = FileManager.default.fileExists(
            atPath: standardized.appendingPathComponent("title", isDirectory: true).path
        ) ? standardized.appendingPathComponent("title", isDirectory: true) : standardized

        let packetNames: [(PartRole, UInt32, String)] = [
            (.head, 7, "headbrosnansuit"),
            (.body, 8, "suitbond"),
            (.weapon, 9, "chrwppk")
        ]
        var models: [Model] = []
        for (role, handle, name) in packetNames {
            let packetURL = titleRoot.appendingPathComponent("\(name).gepk")
            guard FileManager.default.fileExists(atPath: packetURL.path) else {
                throw Error.missingAsset(packetURL.lastPathComponent)
            }
            let packet: GoldenEyeTitleGeometryPacket
            do {
                packet = try GoldenEyeTitleGeometryPacket.load(from: packetURL)
            } catch {
                throw Error.packet("\(name): \(error)")
            }
            guard packet.modelHandle == handle else {
                throw Error.invalidAsset("\(name) model handle \(packet.modelHandle)")
            }
            let sourceHash = hex(packet.sourceHash)
            guard sourceHash == expectedSourceHashes[handle] else {
                throw Error.invalidAsset("\(name) source hash \(sourceHash)")
            }
            models.append(Model(
                role: role,
                modelHandle: handle,
                name: name,
                sourceSHA256: sourceHash,
                packetSHA256: hex(packet.packetHash),
                sourceLength: packet.sourceLength,
                commandCount: packet.commandCount,
                unsupportedCommandCount: packet.unsupportedCommandCount,
                vertexCount: UInt32(packet.vertices.count),
                indexCount: UInt32(packet.indices.count)
            ))
        }

        let backgroundURL = titleRoot.appendingPathComponent("gunbarrel-background.bin")
        guard FileManager.default.fileExists(atPath: backgroundURL.path) else {
            throw Error.missingAsset(backgroundURL.lastPathComponent)
        }
        let backgroundData = try Data(contentsOf: backgroundURL, options: [.mappedIfSafe])
        guard backgroundData.count >= 10 else { throw Error.invalidAsset("background header") }
        let width = UInt32(backgroundData[0]) << 8 | UInt32(backgroundData[1])
        let height = UInt32(backgroundData[2]) << 8 | UInt32(backgroundData[3])
        guard width == 440, height == 299 else {
            throw Error.invalidAsset("background dimensions \(width)x\(height)")
        }
        var rleCursor = 10
        var decodedPixels = 0
        let expectedPixels = Int(width) * Int(height)
        while decodedPixels < expectedPixels {
            guard rleCursor + 1 < backgroundData.count else {
                throw Error.invalidAsset("background RLE truncation")
            }
            let run = Int(backgroundData[rleCursor])
            guard run > 0, decodedPixels + run <= expectedPixels else {
                throw Error.invalidAsset("background RLE run")
            }
            decodedPixels += run
            rleCursor += 2
        }
        let background = Background(
            width: width,
            height: height,
            encodedByteCount: UInt32(backgroundData.count),
            encodedSHA256: hex(SHA256.hash(data: backgroundData))
        )

        // The catalog currently exposes the blood source row as provenance
        // metadata.  If a later preparation run publishes the actual encoded
        // bytes, this loader consumes that bounded payload and verifies it.
        let bloodCandidates = [
            root.appendingPathComponent("payloads/blood/die_blood_image_1.raw"),
            titleRoot.appendingPathComponent("die_blood_image_1.raw")
        ]
        let bloodURL = bloodCandidates.first { FileManager.default.fileExists(atPath: $0.path) }
        let bloodData = bloodURL.flatMap { try? Data(contentsOf: $0, options: [.mappedIfSafe]) }
        if let bloodData {
            guard hex(SHA256.hash(data: bloodData)) == expectedBloodEncodedSHA256,
                  bloodData.count == 2_524 else {
                throw Error.invalidAsset("blood encoded payload hash/size")
            }
        }
        let blood = Blood(
            sourceSHA256: expectedSourceBloodSHA256,
            encodedSHA256: expectedBloodEncodedSHA256,
            encodedByteCount: 2_524,
            sourceWidth: 80,
            sourceHeight: 96,
            textureWidth: 96,
            textureHeight: 80,
            encodedPayloadAvailable: bloodData != nil
        )

        let animation = Animation(
            walkEntryOffset: 0x5484c,
            fireEntryOffset: 0x55198,
            initialPlaySpeedQ16: 0x0000_8000,
            fireStartFrameQ16: 0x0002_0000,
            firePlaySpeedQ16: 0x0000_e956,
            fireSpeedupQ16: 0x0001_999a,
            animationStartSubstep: 137,
            animationSpeedupSubstep: 212,
            rifleCueSubstep: 230
        )
        let attachment = Attachment(
            gunParentSwitch: 3,
            muzzleFlashSwitch: 0,
            muzzleLightSwitch: 2,
            bodyModelHandle: 8,
            headModelHandle: 7,
            weaponModelHandle: 9
        )
        let camera = Camera(
            eyeQ16: SIMD3(115_231_667, 14_417_920, 44_845_068),
            directionQ16: SIMD3(-63_570, 0, 15_729),
            upQ16: SIMD3(0, 65_536, 0),
            fovDegreesQ16: 3_014_656,
            aspectNumerator: 4,
            aspectDenominator: 3,
            nearQ16: 655_360,
            farQ16: 655_360_000
        )
        let manifestHash = stableHash(models: models, background: background, blood: blood)
        return Self(
            models: models.sorted { $0.modelHandle < $1.modelHandle },
            background: background,
            blood: blood,
            animation: animation,
            attachment: attachment,
            camera: camera,
            holeVertexCount: 30,
            holeTriangleCount: 28,
            sourceTitleSHA256: expectedSourceTitleSHA256,
            sourceTitle3SHA256: expectedSourceTitle3SHA256,
            sourceBloodDecryptSHA256: "59941f3ca6d2540c806c73f94a9f200b872d7f84a068bf042841d41984df0e5a",
            manifestHash: manifestHash
        )
    }

    public func manifestLines() -> [String] {
        var lines = [
            "manifest_version=6",
            "route=gunbarrel",
            "runtime_rom_access=false",
            "native_hz=120",
            "reference_hz=60",
            "model_substeps_per_reference_frame=2",
            "source_title_sha256=\(sourceTitleSHA256)",
            "source_title3_sha256=\(sourceTitle3SHA256)",
            "source_blood_decrypt_sha256=\(sourceBloodDecryptSHA256.isEmpty ? "not-published" : sourceBloodDecryptSHA256)",
            "background=\(background.width)x\(background.height):bytes=\(background.encodedByteCount):sha256=\(background.encodedSHA256)",
            "blood=\(blood.sourceWidth)x\(blood.sourceHeight)->\(blood.textureWidth)x\(blood.textureHeight):encoded_bytes=\(blood.encodedByteCount):payload=\(blood.encodedPayloadAvailable ? "present" : "missing")",
            "hole_vertices=\(holeVertexCount)",
            "hole_triangles=\(holeTriangleCount)",
            "camera_eye_q16=\(camera.eyeQ16.x),\(camera.eyeQ16.y),\(camera.eyeQ16.z)",
            "camera_direction_q16=\(camera.directionQ16.x),\(camera.directionQ16.y),\(camera.directionQ16.z)",
            "camera_fov_degrees_q16=\(camera.fovDegreesQ16)",
            "capture_ready=\(captureReady ? "true" : "false")",
            "manifest_hash=\(manifestHash)"
        ]
        for model in models.sorted(by: { $0.modelHandle < $1.modelHandle }) {
            lines.append(
                "model=\(model.modelHandle):role=\(model.role.rawValue):name=\(model.name):source=\(model.sourceSHA256):packet=\(model.packetSHA256):commands=\(model.commandCount):unsupported=\(model.unsupportedCommandCount):vertices=\(model.vertexCount):indices=\(model.indexCount)"
            )
        }
        return lines
    }

    private static func stableHash(
        models: [Model],
        background: Background,
        blood: Blood
    ) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        func mix(_ value: UInt64) {
            hash ^= value
            hash &*= 1_099_511_628_211
        }
        for model in models.sorted(by: { $0.modelHandle < $1.modelHandle }) {
            mix(UInt64(model.role.rawValue)); mix(UInt64(model.modelHandle))
            mix(UInt64(model.commandCount)); mix(UInt64(model.unsupportedCommandCount))
            mix(UInt64(model.vertexCount)); mix(UInt64(model.indexCount))
            for byte in model.sourceSHA256.utf8 { mix(UInt64(byte)) }
            for byte in model.packetSHA256.utf8 { mix(UInt64(byte)) }
        }
        mix(UInt64(background.width)); mix(UInt64(background.height))
        mix(UInt64(background.encodedByteCount))
        mix(UInt64(blood.encodedPayloadAvailable ? 1 : 0))
        mix(UInt64(blood.encodedByteCount)); mix(UInt64(blood.sourceWidth)); mix(UInt64(blood.sourceHeight))
        return hash
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Prepared dynamic model data for the Gunbarrel route.  The packet keeps
/// the original compressed clip words and source skeleton joint selectors;
/// the runtime decodes one pose from those values for each immutable frame.
public struct GoldenEyeGunbarrelAnimationClipV6: Sendable, Equatable {
    public let name: String
    public let entryOffset: UInt32
    public let dataOffset: UInt32
    public let descriptorOffset: UInt32
    public let bitStreamOffset: UInt32
    public let frameCount: UInt32
    public let bitWidth: UInt32
    public let loopFlags: UInt32
    public let bitStride: UInt32
    public let frameBits: UInt32
    public let frameBytes: UInt32
    public let entrySHA256: String
    public let entryWords: [UInt32]
    public let rootMotionDescriptors: [GoldenEyeGunbarrelRootMotionDescriptorV6]
    public let rootMotionDescriptorSHA256: String
}

public struct GoldenEyeGunbarrelRootMotionDescriptorV6: Sendable, Equatable {
    public let bitOffset: UInt16
    public let bitCount: UInt8
    public let valueOffset: UInt16
}

public struct GoldenEyeGunbarrelSkeletonJointV6: Sendable, Equatable {
    public let nodeType: UInt32
    public let matrixA: UInt32
    public let matrixB: UInt32
}

public struct GoldenEyeGunbarrelSkeletonV6: Sendable, Equatable {
    public let name: String
    public let sourcePath: String
    public let sourceSHA256: String
    public let skeletonSize: UInt32
    public let joints: [GoldenEyeGunbarrelSkeletonJointV6]

    public var handle: UInt32 {
        switch name {
        case "guard": return 0xD601_0001
        case "standard_gun": return 0xD601_0002
        case "gun_kf7": return 0xD601_0003
        default: return 0xD601_FF00
        }
    }
}

public struct GoldenEyeGunbarrelAttachmentPoseV6: Sendable, Equatable {
    public let bodyModelHandle: UInt32
    public let headModelHandle: UInt32
    public let weaponModelHandle: UInt32
    public let weaponParentSwitch: UInt32
    public let muzzleFlashSwitch: UInt32
    public let muzzleLightSwitch: UInt32
    public let gunfireOriginQ16: SIMD3<Int32>
    public let gunfireTargetQ16: SIMD3<Int32>
    public let sourcePath: String
    public let sourceSHA256: String
}

public struct GoldenEyeGunbarrelPoseV6: Sendable, Equatable {
    public let modelHandle: UInt32
    public let skeletonHandle: UInt32
    public let nodeHandle: UInt32
    public let parentHandle: UInt32
    public let jointIndex: UInt32
    public let animationTick: UInt32
    public let translationQ16: SIMD3<Int32>
    public let rotationQ16: SIMD4<Int32>
    public let scaleQ16: SIMD3<Int32>
    public let rawAngles: SIMD3<UInt16>
    public let poseHash: UInt64

    #if canImport(GoldenEyeNative)
    func sourceRecord(flags: UInt32 = UInt32(GE_SOURCE_POSE_V6_FLAG_INTERPOLATABLE)) -> GESourceAnimationPoseV6 {
        var value = GESourceAnimationPoseV6()
        value.header.abi_version = GE_NATIVE_ABI_VERSION
        value.header.struct_size = UInt32(MemoryLayout<GESourceAnimationPoseV6>.size)
        value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        value.pose_handle = poseHashHandle
        value.skeleton_handle = skeletonHandle
        value.node_handle = nodeHandle
        value.parent_handle = parentHandle
        value.flags = flags
        value.animation_tick = animationTick
        value.reserved0 = 0
        value.translation_q16 = (translationQ16.x, translationQ16.y, translationQ16.z)
        value.rotation_q16 = (rotationQ16.x, rotationQ16.y, rotationQ16.z, rotationQ16.w)
        value.scale_q16 = (scaleQ16.x, scaleQ16.y, scaleQ16.z)
        value.pose_hash = poseHash
        value.reserved1 = 0
        value.reserved2 = 0
        return value
    }

    private var poseHashHandle: UInt32 {
        UInt32(truncatingIfNeeded: poseHash | 0xD700_0000)
    }
    #endif
}

/// Value-only resolver for GESM's dynamic Gunbarrel model dependency.  The
/// source-model compiler uses this resolver to decide whether the three
/// character/weapon graphs may be traversed; it never stores the resolver or
/// any source pointer in a scene packet.
public struct GoldenEyeGunbarrelDynamicSidecarV6: Sendable, Equatable {
    public enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case invalid(String)
        case hashMismatch(expected: String, actual: String)
        case missingClip(String)
        case missingSkeleton(String)
        case invalidFrame(String)

        public var description: String {
            switch self {
            case .invalid(let value): return "Gunbarrel dynamic sidecar invalid: \(value)"
            case .hashMismatch(let expected, let actual): return "Gunbarrel dynamic sidecar hash \(actual) != \(expected)"
            case .missingClip(let value): return "Gunbarrel dynamic clip missing: \(value)"
            case .missingSkeleton(let value): return "Gunbarrel dynamic skeleton missing: \(value)"
            case .invalidFrame(let value): return "Gunbarrel dynamic frame invalid: \(value)"
            }
        }
    }

    public let packetSHA256: String
    public let clips: [GoldenEyeGunbarrelAnimationClipV6]
    public let skeletons: [GoldenEyeGunbarrelSkeletonV6]
    public let attachment: GoldenEyeGunbarrelAttachmentPoseV6
    public let models: [UInt32: String]
    public let bloodEncoded: Data
    public let bloodSourceSHA256: String

    private init(
        packetSHA256: String,
        clips: [GoldenEyeGunbarrelAnimationClipV6],
        skeletons: [GoldenEyeGunbarrelSkeletonV6],
        attachment: GoldenEyeGunbarrelAttachmentPoseV6,
        models: [UInt32: String],
        bloodEncoded: Data,
        bloodSourceSHA256: String
    ) {
        self.packetSHA256 = packetSHA256
        self.clips = clips
        self.skeletons = skeletons
        self.attachment = attachment
        self.models = models
        self.bloodEncoded = bloodEncoded
        self.bloodSourceSHA256 = bloodSourceSHA256
    }

    public init(loading url: URL) throws {
        self = try Self.load(from: url)
    }

    public static func load(from url: URL) throws -> Self {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packetSHA = root["packet_sha256"] as? String else {
            throw Error.invalid("JSON envelope")
        }
        var unsigned = root
        unsigned.removeValue(forKey: "packet_sha256")
        let canonical = try JSONSerialization.data(withJSONObject: unsigned, options: [.sortedKeys, .withoutEscapingSlashes])
        let actual = hex(SHA256.hash(data: canonical))
        guard actual == packetSHA else { throw Error.hashMismatch(expected: packetSHA, actual: actual) }
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        guard wire.packetSHA256 == packetSHA else { throw Error.invalid("packet digest field") }
        guard wire.magic == "GEGB", wire.version == 6, wire.route == "gunbarrel", !wire.runtimeROMAccess else {
            throw Error.invalid("identity/runtime ROM guard")
        }
        let clips = wire.clips.map { clip in
            GoldenEyeGunbarrelAnimationClipV6(
                name: clip.name,
                entryOffset: clip.entryOffset,
                dataOffset: clip.dataOffset,
                descriptorOffset: clip.descriptorOffset,
                bitStreamOffset: clip.bitStreamOffset,
                frameCount: clip.frameCount,
                bitWidth: clip.bitWidth,
                loopFlags: clip.loopFlags,
                bitStride: clip.bitStride,
                frameBits: clip.frameBits,
                frameBytes: clip.frameBytes,
                entrySHA256: clip.entrySHA256,
                entryWords: clip.entryWords,
                rootMotionDescriptors: clip.rootMotionDescriptors.map {
                    GoldenEyeGunbarrelRootMotionDescriptorV6(
                        bitOffset: $0.bitOffset,
                        bitCount: $0.bitCount,
                        valueOffset: $0.valueOffset
                    )
                },
                rootMotionDescriptorSHA256: clip.rootMotionDescriptorSHA256
            )
        }
        for clip in clips {
            guard clip.frameCount > 0, clip.bitWidth > 0, clip.bitWidth <= 16,
                  clip.frameBytes > 0, clip.entryWords.count * 4 == Int(clip.frameCount * clip.frameBytes),
                  hex(SHA256.hash(data: clip.entryWords.reduce(into: Data()) { data, word in
                      var be = word.bigEndian
                      withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
                  })) == clip.entrySHA256,
                  clip.rootMotionDescriptors.count == 4,
                  hex(SHA256.hash(data: clip.rootMotionDescriptors.reduce(into: Data()) { data, descriptor in
                      var bitOffset = descriptor.bitOffset.bigEndian
                      let bitCount = descriptor.bitCount
                      let padding: UInt8 = 0
                      var valueOffset = descriptor.valueOffset.bigEndian
                      withUnsafeBytes(of: &bitOffset) { data.append(contentsOf: $0) }
                      data.append(bitCount)
                      data.append(padding)
                      withUnsafeBytes(of: &valueOffset) { data.append(contentsOf: $0) }
                  })) == clip.rootMotionDescriptorSHA256 else {
                throw Error.invalid("clip \(clip.name) bounds/hash")
            }
        }
        let skeletons = wire.skeletons.map { skeleton in
            GoldenEyeGunbarrelSkeletonV6(
                name: skeleton.name,
                sourcePath: skeleton.sourcePath,
                sourceSHA256: skeleton.sourceSHA256,
                skeletonSize: skeleton.skeletonSize,
                joints: skeleton.joints.map {
                    GoldenEyeGunbarrelSkeletonJointV6(nodeType: $0.nodeType, matrixA: $0.mtxA, matrixB: $0.mtxB)
                }
            )
        }
        var models: [UInt32: String] = [:]
        for model in wire.models {
            guard models.updateValue(model.role, forKey: model.modelHandle) == nil else {
                throw Error.invalid("duplicate model handle \(model.modelHandle)")
            }
            if let sourceModelHandle = model.sourceModelHandle {
                guard models.updateValue(model.role, forKey: sourceModelHandle) == nil else {
                    throw Error.invalid("duplicate source model handle \(sourceModelHandle)")
                }
            }
        }
        guard Set(models.values) == Set(["head", "body", "weapon"]),
              wire.models.count == 3,
              wire.models.allSatisfy({ $0.modelHandle != 0 }),
              wire.attachment.gunfireOriginQ16.count == 3,
              wire.attachment.gunfireTargetQ16.count == 3 else {
            throw Error.invalid("model/attachment linkage")
        }
        let attachment = GoldenEyeGunbarrelAttachmentPoseV6(
            bodyModelHandle: wire.attachment.bodyModelHandle,
            headModelHandle: wire.attachment.headModelHandle,
            weaponModelHandle: wire.attachment.weaponModelHandle,
            weaponParentSwitch: wire.attachment.weaponParentSwitch,
            muzzleFlashSwitch: wire.attachment.muzzleFlashSwitch,
            muzzleLightSwitch: wire.attachment.muzzleLightSwitch,
            gunfireOriginQ16: SIMD3(wire.attachment.gunfireOriginQ16[0], wire.attachment.gunfireOriginQ16[1], wire.attachment.gunfireOriginQ16[2]),
            gunfireTargetQ16: SIMD3(wire.attachment.gunfireTargetQ16[0], wire.attachment.gunfireTargetQ16[1], wire.attachment.gunfireTargetQ16[2]),
            sourcePath: wire.attachment.gunfireSourcePath,
            sourceSHA256: wire.attachment.gunfireSourceSHA256
        )
        let blood = Data(wire.blood.encodedBytes)
        guard blood.count == Int(wire.blood.encodedByteCount),
              hex(SHA256.hash(data: blood)) == wire.blood.encodedSHA256,
              wire.blood.sourceWidth == 80, wire.blood.sourceHeight == 96,
              wire.blood.textureWidth == 96, wire.blood.textureHeight == 80 else {
            throw Error.invalid("blood payload envelope/hash")
        }
        return Self(
            packetSHA256: packetSHA,
            clips: clips,
            skeletons: skeletons,
            attachment: attachment,
            models: models,
            bloodEncoded: blood,
            bloodSourceSHA256: wire.blood.sourceSHA256
        )
    }

    public var resolvesGunbarrelModels: Bool {
        Set(models.values) == Set(["head", "body", "weapon"])
            && Set([7, 8, 9]).isSubset(of: Set(models.keys))
            && clips.contains(where: { $0.name == "bond_eye_walk" })
            && clips.contains(where: { $0.name == "bond_eye_fire" })
            && skeletons.contains(where: { $0.name == "guard" && $0.joints.count == 16 })
            && skeletons.contains(where: { $0.name == "gun_kf7" && $0.joints.count == 7 })
            && attachment.weaponParentSwitch == 3
            && attachment.muzzleFlashSwitch == 0
            && attachment.muzzleLightSwitch == 2
    }

    public var dynamicResolver: GESourceModelDynamicResolverV6 {
        GESourceModelDynamicResolverV6(resolvedModels: resolvesGunbarrelModels ? Set(["headbrosnansuit", "suitbond", "chrwppk"]) : [])
    }

    public func clip(named name: String) throws -> GoldenEyeGunbarrelAnimationClipV6 {
        guard let clip = clips.first(where: { $0.name == name }) else { throw Error.missingClip(name) }
        return clip
    }

    public func skeleton(named name: String) throws -> GoldenEyeGunbarrelSkeletonV6 {
        guard let skeleton = skeletons.first(where: { $0.name == name }) else { throw Error.missingSkeleton(name) }
        return skeleton
    }

    /// Integrate one source Gunbarrel timer as one native model substep. The
    /// timer is reset on Gunbarrel entry and is independent of the frontend
    /// menu timer. Root X/Z are accumulated across every crossed animation
    /// frame, with source heading rotation, loop wrapping, fire transition,
    /// and the 212 speed ramp preserved.
    public func integratedRootMotion(sourceSubstep: UInt32) throws -> IntegratedRootMotionV6 {
        guard sourceSubstep <= 100_000 else {
            throw Error.invalid("root-motion substep capacity")
        }
        let walk = try clip(named: "bond_eye_walk")
        guard walk.frameCount > 0 else { throw Error.invalid("empty walk root-motion clip") }
        let walkCount = Int(walk.frameCount)
        let walkStartFrame = UInt32((walkCount - (0x44 % walkCount)) % walkCount)
        var accumulator = try RootMotionAccumulatorV6(
            sidecar: self,
            clipName: "bond_eye_walk",
            frame: walkStartFrame
        )
        var mergeWalk: RootMotionAccumulatorV6?
        var mergeTicks = 0
        var result = try accumulator.result()
        if sourceSubstep > 0 {
            for tick in UInt32(1)...sourceSubstep {
                if tick == 137 {
                    mergeWalk = accumulator
                    try accumulator.switchClip("bond_eye_fire", frame: 2)
                    mergeTicks = 0
                }
                let speed: Double
                if tick < 212 {
                    speed = 0.91
                } else {
                    let elapsed = min(8.0, Double(tick - 211) * 0.5)
                    speed = elapsed < 8.0 ? 0.91 + (1.6 - 0.91) * (elapsed / 8.0) : 1.6
                }
                let crossed = try accumulator.advance(
                    rateQ16: Int64((0.5 * speed * 65_536.0).rounded())
                )
                let fireResult = try accumulator.result()
                if mergeTicks < 32, let walkAccumulator = mergeWalk {
                    mergeTicks += 1
                    if crossed {
                        accumulator.applyMergeVelocity(
                            from: walkAccumulator,
                            speed2: 0.91,
                            speed: speed,
                            playspeed: 0.5,
                            elapsed: Double(mergeTicks) * 0.5,
                            mergeDuration: 16.0
                        )
                    }
                    result = try accumulator.result()
                } else {
                    result = fireResult
                }
            }
        }
        return result
    }

    /// Select the exact source animation clip/frame for a Gunbarrel source
    /// timer. These fixed-point rates are the values supplied to
    /// `modelSetAnimation`/`modelSetAnimSpeed` in title.c; this method only
    /// selects a bounded copied packet frame and never advances state.
    public func animationPoseSelection(sourceTimer: UInt32) throws -> (clipName: String, frame: UInt32) {
        let integrated = try integratedRootMotion(sourceSubstep: sourceTimer)
        let clip = try self.clip(named: integrated.clipName)
        return (
            integrated.clipName,
            UInt32((integrated.frameQ16 >> 16) % Int64(clip.frameCount))
        )
    }

    public struct RootMotionV6: Sendable, Equatable {
        public let translationQ16: SIMD3<Int32>
        public let headingQ16: Int32
        public let scaleQ16: Int32
        public let descriptorHash: String
    }

    /// Accumulated value-only root state matching modelSetAnimFrame2WithChrStuff.
    public struct IntegratedRootMotionV6: Sendable, Equatable {
        public let translationQ16: SIMD3<Int32>
        public let headingQ16: Int32
        public let frameQ16: Int64
        public let clipName: String
        public let descriptorHash: String
    }

    private struct RootMotionAccumulatorV6 {
        let sidecar: GoldenEyeGunbarrelDynamicSidecarV6
        var clipName: String
        var frameQ16: Int64
        var baseTranslationQ16 = SIMD3<Int64>(repeating: 0)
        var baseHeadingQ16: Int64 = 0
        var currentTranslationQ16 = SIMD3<Int64>(repeating: 0)
        var currentHeadingQ16: Int64 = 0
        var lastFraction: Double = 0
        var lastNextDelta = SIMD3<Double>(repeating: 0)

        private let tauQ16: Int64 = 411_775

        init(sidecar: GoldenEyeGunbarrelDynamicSidecarV6, clipName: String, frame: UInt32) throws {
            self.sidecar = sidecar
            self.clipName = clipName
            let clip = try sidecar.clip(named: clipName)
            guard clip.frameCount > 0 else { throw Error.invalid("empty root-motion clip") }
            self.frameQ16 = Self.normalizedFrame(Int64(frame) << 16, frameCount: Int(clip.frameCount))
            let nextIndex = (Int(frame) + 1) % Int(clip.frameCount)
            let next = try sidecar.rootMotion(clipName: clipName, frame: UInt32(nextIndex))
            self.baseTranslationQ16.y = Int64(next.translationQ16.y)
            self.currentTranslationQ16.y = Int64(next.translationQ16.y)
        }

        mutating func switchClip(_ name: String, frame: UInt32) throws {
            baseTranslationQ16 = currentTranslationQ16
            baseHeadingQ16 = currentHeadingQ16
            clipName = name
            let clip = try sidecar.clip(named: name)
            guard clip.frameCount > 0 else { throw Error.invalid("empty root-motion clip") }
            frameQ16 = Self.normalizedFrame(Int64(frame) << 16, frameCount: Int(clip.frameCount))
            currentTranslationQ16 = baseTranslationQ16
            currentHeadingQ16 = baseHeadingQ16
        }

        @discardableResult
        mutating func advance(rateQ16: Int64) throws -> Bool {
            let clip = try sidecar.clip(named: clipName)
            let frameCount = Int(clip.frameCount)
            guard frameCount > 0 else { throw Error.invalid("empty root-motion clip") }
            let oldFrameQ16 = Self.constrainedFrame(
                frameQ16,
                frameCount: frameCount,
                looping: clip.loopFlags != 0
            )
            let rawNextFrameQ16 = oldFrameQ16 &+ rateQ16
            let nextFrameQ16 = clip.loopFlags != 0
                ? rawNextFrameQ16
                : min(rawNextFrameQ16, Int64(frameCount - 1) << 16)
            let oldFloor = oldFrameQ16 >> 16
            let nextFloor = nextFrameQ16 >> 16
            let crossed = nextFloor > oldFloor
            if crossed {
                for boundary in (oldFloor + 1)...nextFloor {
                    let index = Int(boundary % Int64(frameCount))
                    try commit(delta: sidecar.rootMotion(clipName: clipName, frame: UInt32(index)))
                }
            }
            frameQ16 = clip.loopFlags != 0
                ? Self.normalizedFrame(nextFrameQ16, frameCount: frameCount)
                : nextFrameQ16
            let fraction = Double(nextFrameQ16 & 0xffff) / 65_536.0
            let atTerminal = clip.loopFlags == 0 && nextFrameQ16 >= (Int64(frameCount - 1) << 16)
            let nextIndex = atTerminal
                ? frameCount - 1
                : Int((nextFloor + 1) % Int64(frameCount))
            let next = try sidecar.rootMotion(clipName: clipName, frame: UInt32(nextIndex))
            let rotated = rotate(next.translationQ16, headingQ16: baseHeadingQ16)
            lastFraction = fraction
            lastNextDelta = rotated
            currentTranslationQ16 = SIMD3(
                baseTranslationQ16.x + Int64((rotated.x * fraction).rounded()),
                baseTranslationQ16.y + Int64((Double(next.translationQ16.y) - Double(baseTranslationQ16.y)) * fraction),
                baseTranslationQ16.z + Int64((rotated.z * fraction).rounded())
            )
            currentHeadingQ16 = baseHeadingQ16 + Int64((Double(next.headingQ16) * fraction).rounded())
            currentHeadingQ16 %= tauQ16
            if currentHeadingQ16 < 0 { currentHeadingQ16 &+= tauQ16 }
            return crossed
        }

        mutating func applyMergeVelocity(
            from secondary: RootMotionAccumulatorV6,
            speed2: Double,
            speed: Double,
            playspeed: Double,
            elapsed: Double,
            mergeDuration: Double
        ) {
            guard speed > 0, mergeDuration > 0 else { return }
            let unk84 = max(0, (mergeDuration - elapsed) / mergeDuration)
            let t0 = unk84 - playspeed / (speed * mergeDuration)
            let t = (unk84 + t0) * 0.5
            let secondaryVelocity = secondary.lastNextDelta * (speed2 / speed)
            let blended = lastNextDelta + (secondaryVelocity - lastNextDelta) * t
            currentTranslationQ16.x = baseTranslationQ16.x + Int64((blended.x * lastFraction).rounded())
            currentTranslationQ16.z = baseTranslationQ16.z + Int64((blended.z * lastFraction).rounded())
        }

        func result() throws -> IntegratedRootMotionV6 {
            let clip = try sidecar.clip(named: clipName)
            return IntegratedRootMotionV6(
                translationQ16: SIMD3(
                    Int32(clamping: currentTranslationQ16.x),
                    Int32(clamping: currentTranslationQ16.y),
                    Int32(clamping: currentTranslationQ16.z)
                ),
                headingQ16: Int32(clamping: currentHeadingQ16),
                frameQ16: frameQ16,
                clipName: clipName,
                descriptorHash: clip.rootMotionDescriptorSHA256
            )
        }

        private mutating func commit(delta: RootMotionV6) throws {
            let rotated = rotate(delta.translationQ16, headingQ16: baseHeadingQ16)
            baseTranslationQ16.x &+= Int64(rotated.x.rounded())
            baseTranslationQ16.y = Int64(delta.translationQ16.y)
            baseTranslationQ16.z &+= Int64(rotated.z.rounded())
            baseHeadingQ16 = (baseHeadingQ16 &+ Int64(delta.headingQ16)) % tauQ16
            if baseHeadingQ16 < 0 { baseHeadingQ16 &+= tauQ16 }
            currentHeadingQ16 = baseHeadingQ16
        }

        private func rotate(_ translation: SIMD3<Int32>, headingQ16: Int64) -> SIMD3<Double> {
            let angle = Double(headingQ16) / 65_536.0
            let cosine = cos(angle)
            let sine = sin(angle)
            let x = Double(translation.x)
            let z = Double(translation.z)
            return SIMD3(x * cosine + z * sine, 0, -x * sine + z * cosine)
        }

        private static func normalizedFrame(_ value: Int64, frameCount: Int) -> Int64 {
            let span = Int64(frameCount) << 16
            let remainder = value % span
            return remainder >= 0 ? remainder : remainder &+ span
        }

        private static func constrainedFrame(
            _ value: Int64,
            frameCount: Int,
            looping: Bool
        ) -> Int64 {
            if looping {
                return normalizedFrame(value, frameCount: frameCount)
            }
            let last = Int64(frameCount - 1) << 16
            return max(0, min(value, last))
        }
    }

    /// Decode modelAnimReadRootMotionValue/sub_GAME_7F06D2E4 from the
    /// source descriptor table and the copied compressed frame stream.
    public func rootMotion(
        clipName: String,
        frame: UInt32,
        flip: Bool = false,
        translationScaleQ16: Int32 = 12_307
    ) throws -> RootMotionV6 {
        let clip = try self.clip(named: clipName)
        guard frame < clip.frameCount, clip.rootMotionDescriptors.count == 4 else {
            throw Error.invalidFrame("\(clipName) root motion frame \(frame)")
        }
        let stream = clip.entryWords.reduce(into: Data()) { data, word in
            var be = word.bigEndian
            withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
        }
        let frameBase = UInt64(frame) * UInt64(clip.frameBits)
        func value(_ descriptor: GoldenEyeGunbarrelRootMotionDescriptorV6) -> Int32 {
            guard descriptor.bitCount > 0 else { return Int32(descriptor.valueOffset) }
            let raw = Self.readBits(
                stream,
                bitOffset: Int(frameBase + UInt64(descriptor.bitOffset)),
                width: Int(descriptor.bitCount)
            )
            var signed = Int32(raw)
            if descriptor.bitCount < 16,
               raw & (UInt16(1) << UInt16(descriptor.bitCount - 1)) != 0 {
                signed |= Int32(bitPattern: 0xffff_ffff << UInt32(descriptor.bitCount))
            }
            return Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: signed + Int32(descriptor.valueOffset))))
        }
        let values = clip.rootMotionDescriptors.map(value)
        var x = Int64(values[0]) * Int64(translationScaleQ16)
        let y = Int64(values[1]) * Int64(translationScaleQ16)
        let z = Int64(values[2]) * Int64(translationScaleQ16)
        var heading = Int64(values[3]) * 411_775 / 65_536
        if flip {
            x = -x
            if values[3] != 0 {
                heading = Int64(0x10000) * 411_775 / 65_536 - heading
            }
        }
        return RootMotionV6(
            translationQ16: SIMD3(
                Int32(clamping: x),
                Int32(clamping: y),
                Int32(clamping: z)
            ),
            headingQ16: Int32(clamping: heading),
            scaleQ16: translationScaleQ16,
            descriptorHash: clip.rootMotionDescriptorSHA256
        )
    }

    /// Decode source packed joint rotations for one clip frame. The bit
    /// extraction intentionally follows modelAnimReadBitsAsU16Angle exactly,
    /// including its high-bit alignment and source-side mirror handling.
    public func poses(
        modelHandle: UInt32,
        clipName: String,
        frame: UInt32,
        flip: Bool = false,
        translationScaleQ16: Int32 = 12_307,
        integratedRootMotion: IntegratedRootMotionV6? = nil
    ) throws -> [GoldenEyeGunbarrelPoseV6] {
        guard let role = models[modelHandle] else { throw Error.invalid("model handle \(modelHandle)") }
        let skeletonName = role == "weapon" ? "gun_kf7" : "guard"
        let clip = try self.clip(named: clipName)
        let skeleton = try self.skeleton(named: skeletonName)
        guard frame < clip.frameCount else { throw Error.invalidFrame("\(clipName) frame \(frame)") }
        let stream = clip.entryWords.reduce(into: Data()) { data, word in
            var be = word.bigEndian
            withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
        }
        let frameBase = Int(frame) * Int(clip.frameBytes)
        let rootMotionValue: RootMotionV6?
        if role == "body" {
            if let integratedRootMotion {
                rootMotionValue = RootMotionV6(
                    translationQ16: integratedRootMotion.translationQ16,
                    headingQ16: integratedRootMotion.headingQ16,
                    scaleQ16: translationScaleQ16,
                    descriptorHash: integratedRootMotion.descriptorHash
                )
            } else {
                rootMotionValue = try rootMotion(
                    clipName: clipName,
                    frame: frame,
                    flip: flip,
                    translationScaleQ16: translationScaleQ16
                )
            }
        } else {
            rootMotionValue = nil
        }
        var result: [GoldenEyeGunbarrelPoseV6] = []
        result.reserveCapacity(skeleton.joints.count)
        for (jointIndex, joint) in skeleton.joints.enumerated() {
            let base = Int(flip ? joint.matrixB : joint.matrixA) * Int(clip.bitWidth)
            let raw0 = readAngle(stream, bitOffset: frameBase * 8 + base, width: Int(clip.bitWidth))
            let raw1Original = readAngle(stream, bitOffset: frameBase * 8 + base + Int(clip.bitWidth), width: Int(clip.bitWidth))
            let raw2Original = readAngle(stream, bitOffset: frameBase * 8 + base + Int(clip.bitWidth * 2), width: Int(clip.bitWidth))
            let raw1 = flip && raw1Original != 0 ? UInt16(0x1_0000 - UInt32(raw1Original)) : raw1Original
            let raw2 = flip && raw2Original != 0 ? UInt16(0x1_0000 - UInt32(raw2Original)) : raw2Original
            let angles = SIMD3(raw0, raw1, raw2)
            var rotation = SIMD4(
                angleQ16(raw0), angleQ16(raw1), angleQ16(raw2), 65_536
            )
            if jointIndex == 0, role == "body" {
                // The source header is not a GroupRecord and never consumes
                // the joint-0 XYZ tuple through process_02_position. Its
                // orientation is the accumulated heading from
                // modelSetAnimFrame2WithChrStuff; animated groups begin at
                // JointID 1. Retain rawAngles for diagnostics, but do not
                // let their X/Z values turn the assembled character over.
                rotation = SIMD4(
                    0,
                    rootMotionValue?.headingQ16 ?? 0,
                    0,
                    65_536
                )
            }
            let translation = jointIndex == 0
                ? (rootMotionValue?.translationQ16 ?? SIMD3(repeating: 0))
                : SIMD3(repeating: 0)
            // translationScaleQ16 belongs to the decoded root-motion offset;
            // it must not become a second geometric scale on the root bone.
            // modelSetScale applies the character scale once at the source
            // header matrix, while the animation pose remains unit scale.
            let scale = SIMD3<Int32>(repeating: 65_536)
            var hash: UInt64 = 1_469_598_103_934_665_603
            for value in [UInt64(modelHandle), UInt64(skeleton.handle), UInt64(jointIndex), UInt64(frame), UInt64(raw0), UInt64(raw1), UInt64(raw2)] {
                hash ^= value
                hash &*= 1_099_511_628_211
            }
            let nodeHandle = 0xD700_0000 | UInt32(jointIndex + 1)
            result.append(GoldenEyeGunbarrelPoseV6(
                modelHandle: modelHandle,
                skeletonHandle: skeleton.handle,
                nodeHandle: nodeHandle,
                parentHandle: jointIndex == 0 ? 0 : (0xD700_0000 | UInt32(jointIndex)),
                jointIndex: UInt32(jointIndex),
                animationTick: frame,
                translationQ16: translation,
                rotationQ16: rotation,
                scaleQ16: scale,
                rawAngles: angles,
                poseHash: hash == 0 ? 1 : hash
            ))
        }
        return result
    }

    #if canImport(GoldenEyeNative)
    public func sourcePoseRecords(
        modelHandle: UInt32,
        clipName: String,
        frame: UInt32,
        flip: Bool = false,
        translationScaleQ16: Int32 = 12_307,
        integratedRootMotion: IntegratedRootMotionV6? = nil
    ) throws -> [GESourceAnimationPoseV6] {
        try poses(
            modelHandle: modelHandle,
            clipName: clipName,
            frame: frame,
            flip: flip,
            translationScaleQ16: translationScaleQ16,
            integratedRootMotion: integratedRootMotion
        ).map { pose in
            var flags = UInt32(GE_SOURCE_POSE_V6_FLAG_INTERPOLATABLE)
            if pose.jointIndex == 0 { flags |= UInt32(GE_SOURCE_POSE_V6_FLAG_ROOT) }
            if pose.modelHandle == attachment.weaponModelHandle { flags |= UInt32(GE_SOURCE_POSE_V6_FLAG_WEAPON_ATTACHMENT) }
            return pose.sourceRecord(flags: flags)
        }
    }
    #endif

    private static func readAngle(_ data: Data, bitOffset: Int, width: Int) -> UInt16 {
        guard width > 0, width <= 16, bitOffset >= 0, bitOffset + width <= data.count * 8 else { return 0 }
        var remaining = width
        var offset = bitOffset
        var value: UInt32 = 0
        while remaining >= 8 - (offset & 7) {
            let bitsThisByte = 8 - (offset & 7)
            remaining -= bitsThisByte
            let byte = UInt32(data[offset >> 3])
            value |= (byte & ((1 << bitsThisByte) - 1)) << remaining
            offset = ((offset >> 3) + 1) << 3
        }
        if remaining > 0 {
            let byte = UInt32(data[offset >> 3])
            value |= (byte >> (8 - (offset & 7) - remaining)) & ((1 << remaining) - 1)
        }
        return UInt16((value << (16 - width)) & 0xffff)
    }

    private static func readBits(_ data: Data, bitOffset: Int, width: Int) -> UInt16 {
        guard width > 0, width <= 16, bitOffset >= 0,
              bitOffset + width <= data.count * 8 else { return 0 }
        var value: UInt32 = 0
        for index in 0..<width {
            let absolute = bitOffset + index
            let byte = UInt32(data[absolute >> 3])
            let bit = (byte >> UInt32(7 - (absolute & 7))) & 1
            value = (value << 1) | bit
        }
        return UInt16(value)
    }

    private func readAngle(_ data: Data, bitOffset: Int, width: Int) -> UInt16 {
        Self.readAngle(data, bitOffset: bitOffset, width: width)
    }

    private func angleQ16(_ raw: UInt16) -> Int32 {
        // 2π in Q16.16, with the source's u16 angle domain retained.
        let tauQ16: Int64 = 411_775
        return Int32((Int64(raw) * tauQ16) >> 16)
    }

    private struct Wire: Codable {
        let magic: String
        let version: UInt32
        let route: String
        let runtimeROMAccess: Bool
        let packetSHA256: String
        let models: [WireModel]
        let clips: [WireClip]
        let skeletons: [WireSkeleton]
        let attachment: WireAttachment
        let blood: WireBlood

        enum CodingKeys: String, CodingKey {
            case magic, version, route, runtimeROMAccess = "runtime_rom_access", packetSHA256 = "packet_sha256", models, clips, skeletons, attachment, blood
        }
    }
    private struct WireModel: Codable { let role: String; let modelHandle: UInt32; let sourceModelHandle: UInt32?; enum CodingKeys: String, CodingKey { case role; case modelHandle = "model_handle"; case sourceModelHandle = "source_model_handle" } }
    private struct WireClip: Codable {
        let name: String; let entryOffset: UInt32; let dataOffset: UInt32; let descriptorOffset: UInt32; let bitStreamOffset: UInt32; let frameCount: UInt32; let bitWidth: UInt32; let loopFlags: UInt32; let bitStride: UInt32; let frameBits: UInt32; let frameBytes: UInt32; let entrySHA256: String; let entryWords: [UInt32]; let rootMotionDescriptors: [WireRootMotionDescriptor]; let rootMotionDescriptorSHA256: String
        enum CodingKeys: String, CodingKey { case name; case entryOffset = "entry_offset"; case dataOffset = "data_offset"; case descriptorOffset = "descriptor_offset"; case bitStreamOffset = "bit_stream_offset"; case frameCount = "frame_count"; case bitWidth = "bit_width"; case loopFlags = "loop_flags"; case bitStride = "bit_stride"; case frameBits = "frame_bits"; case frameBytes = "frame_bytes"; case entrySHA256 = "entry_sha256"; case entryWords = "entry_words"; case rootMotionDescriptors = "root_motion_descriptors"; case rootMotionDescriptorSHA256 = "root_motion_descriptor_sha256" }
    }
    private struct WireRootMotionDescriptor: Codable {
        let bitOffset: UInt16
        let bitCount: UInt8
        let valueOffset: UInt16
        enum CodingKeys: String, CodingKey {
            case bitOffset = "bit_offset"
            case bitCount = "bit_count"
            case valueOffset = "value_offset"
        }
    }
    private struct WireSkeleton: Codable { let name: String; let sourcePath: String; let sourceSHA256: String; let skeletonSize: UInt32; let joints: [WireJoint]; enum CodingKeys: String, CodingKey { case name; case sourcePath = "source_path"; case sourceSHA256 = "source_sha256"; case skeletonSize = "skeleton_size"; case joints } }
    private struct WireJoint: Codable { let nodeType: UInt32; let mtxA: UInt32; let mtxB: UInt32; enum CodingKeys: String, CodingKey { case nodeType = "node_type"; case mtxA = "mtx_a"; case mtxB = "mtx_b" } }
    private struct WireAttachment: Codable { let bodyModelHandle: UInt32; let headModelHandle: UInt32; let weaponModelHandle: UInt32; let weaponParentSwitch: UInt32; let muzzleFlashSwitch: UInt32; let muzzleLightSwitch: UInt32; let gunfireOriginQ16: [Int32]; let gunfireTargetQ16: [Int32]; let gunfireSourcePath: String; let gunfireSourceSHA256: String; enum CodingKeys: String, CodingKey { case bodyModelHandle = "body_model_handle"; case headModelHandle = "head_model_handle"; case weaponModelHandle = "weapon_model_handle"; case weaponParentSwitch = "weapon_parent_switch"; case muzzleFlashSwitch = "muzzle_flash_switch"; case muzzleLightSwitch = "muzzle_light_switch"; case gunfireOriginQ16 = "gunfire_origin_q16"; case gunfireTargetQ16 = "gunfire_target_q16"; case gunfireSourcePath = "gunfire_source_path"; case gunfireSourceSHA256 = "gunfire_source_sha256" } }
    private struct WireBlood: Codable { let sourcePath: String; let sourceSHA256: String; let encodedSHA256: String; let encodedByteCount: UInt32; let sourceWidth: UInt32; let sourceHeight: UInt32; let textureWidth: UInt32; let textureHeight: UInt32; let encodedBytes: [UInt8]; enum CodingKeys: String, CodingKey { case sourcePath = "source_path"; case sourceSHA256 = "source_sha256"; case encodedSHA256 = "encoded_sha256"; case encodedByteCount = "encoded_byte_count"; case sourceWidth = "source_width"; case sourceHeight = "source_height"; case textureWidth = "texture_width"; case textureHeight = "texture_height"; case encodedBytes = "encoded_bytes" } }
}

public struct GoldenEyeGunbarrelCameraFrameV6: Sendable, Equatable {
    public let eyeQ16: SIMD3<Int32>
    public let directionQ16: SIMD3<Int32>
    public let upQ16: SIMD3<Int32>
    public let fovDegreesQ16: UInt32
    public let nearQ16: UInt32
    public let farQ16: UInt32

    public static let source = Self(
        eyeQ16: SIMD3(115_231_667, 14_417_920, 44_845_068),
        directionQ16: SIMD3(-63_570, 0, 15_729),
        upQ16: SIMD3(0, 65_536, 0),
        fovDegreesQ16: 3_014_656,
        nearQ16: 655_360,
        farQ16: 655_360_000
    )
}

public struct GoldenEyeGunbarrelPartFrameV6: Sendable, Equatable {
    public let role: GoldenEyeGunbarrelSourceManifestV6.PartRole
    public let modelHandle: UInt32
    public let visible: Bool
    public let attachmentNode: UInt32
    public let muzzleFlashVisible: Bool
    public let animationEntryOffset: UInt32
    public let animationFrameQ16: Int32
    public let poseHash: UInt64
}

public struct GoldenEyeGunbarrelFrameV6: Sendable, Equatable {
    public enum Fade: UInt32, Sendable, Equatable {
        case none = 0
        case red = 1
        case black = 2
        case clearBlack = 3
    }

    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let pairPhase: UInt32
    public let sourceFrame: UInt32
    public let mode: UInt32
    public let subphase: UInt32
    public let gunbarrelTimerSubstep: UInt32
    public let introEyeCounter: Int32
    public let word: Int32
    public let titleXQ16: Int32
    public let transitionXQ16: Int32
    public let bloodFrameIndex: UInt32
    public let bloodVisible: Bool
    public let muzzleFlashVisible: Bool
    public let backgroundVisible: Bool
    public let holeVisible: Bool
    public let fade: Fade
    public let fadeAlphaQ8: UInt32
    public let camera: GoldenEyeGunbarrelCameraFrameV6
    public let parts: [GoldenEyeGunbarrelPartFrameV6]
    public let poses: [GoldenEyeGunbarrelPoseV6]
    public let rifleCue: Bool
    public let captureReady: Bool
    public let sourceManifestHash: UInt64

    public var redOverlayAlphaQ8: UInt32 {
        switch mode {
        case 6, 7: return 180
        default: return 0
        }
    }

    public var blackOverlayAlphaQ8: UInt32 {
        mode == 7 ? min(fadeAlphaQ8, 248) : 0
    }

    public var clearBlack: Bool { mode == 8 || fade == .clearBlack }

    public var renderHash: UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        func mix(_ value: UInt64) { hash ^= value; hash &*= 1_099_511_628_211 }
        mix(nativeTick); mix(referenceTick); mix(UInt64(pairPhase)); mix(UInt64(sourceFrame))
        mix(UInt64(mode)); mix(UInt64(subphase)); mix(UInt64(gunbarrelTimerSubstep))
        mix(UInt64(bitPattern: Int64(introEyeCounter))); mix(UInt64(bitPattern: Int64(word)))
        mix(UInt64(bitPattern: Int64(titleXQ16))); mix(UInt64(bitPattern: Int64(transitionXQ16)))
        mix(UInt64(bloodFrameIndex)); mix(bloodVisible ? 1 : 0); mix(muzzleFlashVisible ? 1 : 0)
        mix(backgroundVisible ? 1 : 0); mix(holeVisible ? 1 : 0); mix(UInt64(fade.rawValue)); mix(UInt64(fadeAlphaQ8))
        mix(rifleCue ? 1 : 0); mix(sourceManifestHash)
        for part in parts { mix(UInt64(part.modelHandle)); mix(part.visible ? 1 : 0); mix(part.muzzleFlashVisible ? 1 : 0); mix(part.poseHash) }
        for pose in poses { mix(UInt64(pose.modelHandle)); mix(UInt64(pose.jointIndex)); mix(pose.poseHash) }
        return hash
    }
}

/// Source-capture gate for the 320x240 reference path.  It intentionally
/// does not synthesize a screenshot from the title shader: until the generic
/// scene lowerer has consumed every visible command, capture requests return
/// a typed not-ready error and leave no misleading image artifact behind.
public struct GoldenEyeGunbarrelCaptureV6: Sendable, Equatable {
    public enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case notReady(String)
        case frameMismatch

        public var description: String {
            switch self {
            case .notReady(let value): return "gunbarrel capture not ready: \(value)"
            case .frameMismatch: return "gunbarrel capture frame/manifest mismatch"
            }
        }
    }

    public let width: UInt32
    public let height: UInt32
    public let nativeTick: UInt64
    public let sourceFrame: UInt32
    public let renderHash: UInt64
    public let manifestHash: UInt64
    public let sourceModelHashes: [String]

    public static func make(
        frame: GoldenEyeGunbarrelFrameV6,
        manifest: GoldenEyeGunbarrelSourceManifestV6
    ) throws -> Self {
        guard frame.sourceManifestHash == manifest.manifestHash else {
            throw Error.frameMismatch
        }
        guard manifest.captureReady, frame.captureReady else {
            let incompleteModels = manifest.models
                .filter { !$0.complete }
                .map(\.name)
                .joined(separator: ",")
            let blood = manifest.blood.complete ? "ready" : "missing-blood-payload"
            throw Error.notReady(
                "models=\(incompleteModels.isEmpty ? "complete" : incompleteModels);blood=\(blood)"
            )
        }
        return Self(
            width: 320,
            height: 240,
            nativeTick: frame.nativeTick,
            sourceFrame: frame.sourceFrame,
            renderHash: frame.renderHash,
            manifestHash: manifest.manifestHash,
            sourceModelHashes: manifest.models.map(\.sourceSHA256)
        )
    }

}

/// Immutable pass manifest carried alongside the combined source scene. It
/// gives the product renderer an explicit source order for the non-model
/// Gunbarrel work; no pass is silently replaced by a clear or a diagnostic
/// shader when its guarded payload is unavailable.
public struct GoldenEyeGunbarrelRenderPassV6: Sendable, Equatable {
    public let nativeTick: UInt64
    public let mode: UInt32
    public let titleXQ16: Int32
    /// The second source translation used by mode 2.  The original title
    /// draws the generated sight mesh twice during the dot sweep: once at
    /// `g_TitleX` and once at `titleTransitionX`.
    public let transitionXQ16: Int32
    public let bloodFrameIndex: UInt32
    public let modelHandles: [UInt32]
    public let poseCount: UInt32
    public let camera: GoldenEyeGunbarrelCameraFrameV6
    public let backgroundWidth: UInt32
    public let backgroundHeight: UInt32
    public let holeVertexCount: UInt32
    public let holeTriangleCount: UInt32
    public let holePassCount: UInt32
    public let backgroundVisible: Bool
    public let holeVisible: Bool
    public let bloodWidth: UInt32
    public let bloodHeight: UInt32
    public let bloodPayloadAvailable: Bool
    public let bloodVisible: Bool
    public let muzzleFlashVisible: Bool
    public let fade: GoldenEyeGunbarrelFrameV6.Fade
    public let fadeAlphaQ8: UInt32
    public let passHash: UInt64

    public var redOverlayAlphaQ8: UInt32 {
        switch mode {
        case 6, 7: return 180
        default: return 0
        }
    }

    public var blackOverlayAlphaQ8: UInt32 {
        mode == 7 ? min(fadeAlphaQ8, 248) : 0
    }

    public var clearBlack: Bool { mode == 8 || fade == .clearBlack }

    public static func make(
        frame: GoldenEyeGunbarrelFrameV6,
        backgroundWidth: UInt32 = 440,
        backgroundHeight: UInt32 = 299,
        bloodPayloadAvailable: Bool
    ) -> Self {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for value in [
            frame.nativeTick, UInt64(frame.mode), UInt64(bitPattern: Int64(frame.titleXQ16)),
            UInt64(bitPattern: Int64(frame.transitionXQ16)), UInt64(frame.bloodFrameIndex), UInt64(frame.poses.count),
            UInt64(backgroundWidth), UInt64(backgroundHeight),
            UInt64(frame.bloodVisible ? 1 : 0), UInt64(frame.muzzleFlashVisible ? 1 : 0),
            UInt64(bloodPayloadAvailable ? 1 : 0), UInt64(frame.backgroundVisible ? 1 : 0),
            UInt64(frame.holeVisible ? 1 : 0), UInt64(frame.fadeAlphaQ8)
        ] {
            hash ^= value
            hash &*= 1_099_511_628_211
        }
        return Self(
            nativeTick: frame.nativeTick,
            mode: frame.mode,
            titleXQ16: frame.titleXQ16,
            transitionXQ16: frame.transitionXQ16,
            bloodFrameIndex: frame.bloodFrameIndex,
            modelHandles: frame.parts.map(\.modelHandle),
            poseCount: UInt32(frame.poses.count),
            camera: frame.camera,
            backgroundWidth: backgroundWidth,
            backgroundHeight: backgroundHeight,
            holeVertexCount: 30,
            holeTriangleCount: 28,
            holePassCount: frame.mode == 2 && frame.holeVisible ? 2 : (frame.holeVisible ? 1 : 0),
            backgroundVisible: frame.backgroundVisible,
            holeVisible: frame.holeVisible,
            bloodWidth: 96,
            bloodHeight: 80,
            bloodPayloadAvailable: bloodPayloadAvailable,
            bloodVisible: frame.bloodVisible,
            muzzleFlashVisible: frame.muzzleFlashVisible,
            fade: frame.fade,
            fadeAlphaQ8: frame.fadeAlphaQ8,
            passHash: hash == 0 ? 1 : hash
        )
    }

    public static func make(
        nativeTick: UInt64,
        mode: UInt32,
        poseCount: UInt32,
        bloodPayloadAvailable: Bool,
        bloodVisible: Bool,
        muzzleFlashVisible: Bool,
        fade: GoldenEyeGunbarrelFrameV6.Fade,
        fadeAlphaQ8: UInt32,
        titleXQ16: Int32 = -30 * 65_536,
        bloodFrameIndex: UInt32 = 0,
        transitionXQ16: Int32 = -100 * 65_536,
        backgroundVisible: Bool? = nil,
        holeVisible: Bool? = nil
    ) -> Self {
        let resolvedBackgroundVisible = backgroundVisible ?? (mode >= 3 && mode <= 7)
        let resolvedHoleVisible = holeVisible ?? (mode >= 2 && mode <= 7)
        let resolvedHolePassCount: UInt32 = resolvedHoleVisible ? (mode == 2 ? 2 : 1) : 0
        var hash: UInt64 = 1_469_598_103_934_665_603
        for value in [
            nativeTick, UInt64(mode), UInt64(bitPattern: Int64(titleXQ16)),
            UInt64(bitPattern: Int64(transitionXQ16)), UInt64(bloodFrameIndex), UInt64(poseCount),
            UInt64(bloodPayloadAvailable ? 1 : 0), UInt64(bloodVisible ? 1 : 0),
            UInt64(muzzleFlashVisible ? 1 : 0), UInt64(resolvedBackgroundVisible ? 1 : 0),
            UInt64(resolvedHoleVisible ? 1 : 0), UInt64(resolvedHolePassCount), UInt64(fadeAlphaQ8)
        ] {
            hash ^= value
            hash &*= 1_099_511_628_211
        }
        return Self(
            nativeTick: nativeTick,
            mode: mode,
            titleXQ16: titleXQ16,
            transitionXQ16: transitionXQ16,
            bloodFrameIndex: bloodFrameIndex,
            modelHandles: [8, 7, 9],
            poseCount: poseCount,
            camera: .source,
            backgroundWidth: 440,
            backgroundHeight: 299,
            holeVertexCount: 30,
            holeTriangleCount: 28,
            holePassCount: resolvedHolePassCount,
            backgroundVisible: resolvedBackgroundVisible,
            holeVisible: resolvedHoleVisible,
            bloodWidth: 96,
            bloodHeight: 80,
            bloodPayloadAvailable: bloodPayloadAvailable,
            bloodVisible: bloodVisible,
            muzzleFlashVisible: muzzleFlashVisible,
            fade: fade,
            fadeAlphaQ8: fadeAlphaQ8,
            passHash: hash == 0 ? 1 : hash
        )
    }
}

public struct GoldenEyeGunbarrelBloodFrameV6: Sendable, Equatable {
    public let width: UInt32
    public let height: UInt32
    public let pixels: [UInt8]
    public let digest: String
}

public struct GoldenEyeGunbarrelBloodStreamV6: Sendable, Equatable {
    public let frames: [GoldenEyeGunbarrelBloodFrameV6]
    public let encodedByteCount: Int

    public var isComplete: Bool { frames.count == 42 && encodedByteCount == 2_524 }
}

/// A bounded source blood decoder.  It ports the byte-level decoder and the
/// source transpose operation from blood_decrypt.c; it never allocates based
/// on an unchecked stream value.
public enum GoldenEyeGunbarrelBloodDecoderV6 {
    public enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case truncated
        case malformed(String)
        public var description: String {
            switch self {
            case .truncated: return "gunbarrel blood stream truncated"
            case .malformed(let value): return "gunbarrel blood stream malformed: \(value)"
            }
        }
    }

    public static func decodeAll(_ encoded: Data) throws -> GoldenEyeGunbarrelBloodStreamV6 {
        guard encoded.count > 1 else { throw Error.truncated }
        var cursor = 0
        var frames: [GoldenEyeGunbarrelBloodFrameV6] = []
        frames.reserveCapacity(42)
        while cursor < encoded.count {
            let before = cursor
            frames.append(try decodeFrame(encoded, cursor: &cursor))
            guard cursor > before else { throw Error.malformed("decoder made no progress") }
        }
        guard cursor == encoded.count, frames.count == 42 else {
            throw Error.malformed("expected 42 complete frames, got \(frames.count) at byte \(cursor)")
        }
        return GoldenEyeGunbarrelBloodStreamV6(
            frames: frames,
            encodedByteCount: cursor
        )
    }

    public static func decodeInitial(_ encoded: Data) throws -> GoldenEyeGunbarrelBloodFrameV6 {
        var cursor = 0
        return try decodeFrame(encoded, cursor: &cursor)
    }

    private static func decodeFrame(
        _ encoded: Data,
        cursor: inout Int
    ) throws -> GoldenEyeGunbarrelBloodFrameV6 {
        guard cursor + 1 < encoded.count else { throw Error.truncated }
        let sourceWidth = 80
        let sourceHeight = 96
        // blood_decrypt.c keeps temp_v0 (the first byte) constant for every
        // compressed row; it is not the previous command byte.
        let baseValue = encoded[cursor]
        cursor += 1
        var decoded = [UInt8]()
        decoded.reserveCapacity(sourceWidth * sourceHeight)
        var rowsRemaining = sourceHeight
        while rowsRemaining > 0 {
            guard cursor < encoded.count else { throw Error.truncated }
            var value = encoded[cursor]
            cursor += 1
            if value == 0xff {
                var filled = 0
                var color: UInt8 = 0xff
                while true {
                    guard cursor < encoded.count else { throw Error.truncated }
                    value = encoded[cursor]
                    cursor += 1
                    if value == 0xff { break }
                    filled += Int(value)
                    guard filled <= sourceWidth else { throw Error.malformed("row run") }
                    decoded.append(contentsOf: repeatElement(color, count: Int(value)))
                    color ^= 0xff
                }
                while filled < sourceWidth {
                    decoded.append(color)
                    filled += 1
                }
                rowsRemaining -= 1
            } else {
                let rowValue = Int(baseValue) + Int(value & 0x1f)
                let rowCount = Int(value >> 5) + 1
                guard rowValue <= sourceWidth, rowCount <= rowsRemaining else {
                    throw Error.malformed("solid rows")
                }
                for _ in 0..<rowCount {
                    decoded.append(contentsOf: repeatElement(UInt8(0xff), count: rowValue))
                    decoded.append(contentsOf: repeatElement(UInt8(0), count: sourceWidth - rowValue))
                }
                rowsRemaining -= rowCount
            }
        }
        guard decoded.count == sourceWidth * sourceHeight else {
            throw Error.malformed("decoded size \(decoded.count)")
        }

        // bloodImgTranspose(src, 80, 96, dst) maps the source's columns to a
        // 96x80 texture rectangle, preserving the source's row-major output.
        var transposed = [UInt8](repeating: 0, count: decoded.count)
        for y in 0..<sourceHeight {
            for x in 0..<sourceWidth {
                transposed[x * sourceHeight + y] = decoded[y * sourceWidth + x]
            }
        }
        let digest = SHA256.hash(data: Data(transposed)).map { String(format: "%02x", $0) }.joined()
        return GoldenEyeGunbarrelBloodFrameV6(
            width: 96,
            height: 80,
            pixels: transposed,
            digest: digest
        )
    }
}

/// Direct native state adapter for title.c's renderGunbarrelEyeIntroSequence.
///
/// The source's NTSC model callback runs two model substeps per 60 Hz frame.
/// This adapter executes exactly one substep per 120 Hz tick and commits
/// autonomous mode/counter changes only at the even source anchor.  Odd
/// frames are render-only midpoints; they never consume a second source event,
/// RNG value, animation packet, or audio cue.
public struct GoldenEyeGunbarrelRuntimeV6: Sendable {
    public enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case invalidTick(expected: UInt64, actual: UInt64)
        case unsupportedAssets
        public var description: String {
            switch self {
            case .invalidTick(let expected, let actual): return "gunbarrel tick expected \(expected), got \(actual)"
            case .unsupportedAssets: return "gunbarrel source assets are not capture-ready"
            }
        }
    }

    private let manifest: GoldenEyeGunbarrelSourceManifestV6
    private let dynamicSidecar: GoldenEyeGunbarrelDynamicSidecarV6?
    private var nativeTick: UInt64 = 0
    private var sourceFrame: UInt32 = 0
    private var mode: UInt32 = 2
    private var timerSubstep: UInt32 = 0
    private var introEyeCounter: Int32 = 0
    private var word: Int32 = 0x42
    private var titleXQ16: Int32 = -30 * 65_536
    private var transitionXQ16: Int32 = -100 * 65_536
    private var animationEntry: UInt32
    private var animationFrameQ16: Int32 = 0
    private var animationRateQ16: Int32
    private var integratedRootMotion: GoldenEyeGunbarrelDynamicSidecarV6.IntegratedRootMotionV6?
    private var bloodFrameIndex: UInt32 = 0
    private var bloodFrameAvailable: Bool
    private var bloodCompletionAcknowledged: Bool

    public init(
        manifest: GoldenEyeGunbarrelSourceManifestV6,
        bloodFrameAvailable: Bool = false,
        dynamicSidecar: GoldenEyeGunbarrelDynamicSidecarV6? = nil
    ) {
        self.manifest = manifest
        self.dynamicSidecar = dynamicSidecar
        self.animationEntry = manifest.animation.walkEntryOffset
        self.animationRateQ16 = Int32(manifest.animation.initialPlaySpeedQ16)
        self.bloodFrameAvailable = bloodFrameAvailable
        self.bloodCompletionAcknowledged = bloodFrameAvailable
        if let dynamicSidecar,
           let walk = try? dynamicSidecar.clip(named: "bond_eye_walk"),
           walk.frameCount > 0 {
            let frameCount = Int(walk.frameCount)
            let walkStartFrame = (frameCount - (0x44 % frameCount)) % frameCount
            self.animationFrameQ16 = Int32(clamping: Int64(walkStartFrame) << 16)
        }
    }

    public var isComplete: Bool { manifest.captureReady && bloodFrameAvailable }

    public mutating func step(nativeTick requestedTick: UInt64) throws -> GoldenEyeGunbarrelFrameV6 {
        guard requestedTick == nativeTick + 1 else {
            throw Error.invalidTick(expected: nativeTick + 1, actual: requestedTick)
        }
        nativeTick = requestedTick

        // Every model substep advances animation and the source timer.  The
        // source title mode itself advances once per reference frame below.
        timerSubstep &+= 1
        animationFrameQ16 = saturatingAdd(animationFrameQ16, animationRateQ16)
        if timerSubstep == manifest.animation.animationStartSubstep {
            animationEntry = manifest.animation.fireEntryOffset
            animationFrameQ16 = Int32(bitPattern: manifest.animation.fireStartFrameQ16)
            animationRateQ16 = Int32(bitPattern: manifest.animation.firePlaySpeedQ16)
        } else if timerSubstep == manifest.animation.animationSpeedupSubstep {
            animationRateQ16 = Int32(bitPattern: manifest.animation.fireSpeedupQ16)
        }
        if let dynamicSidecar {
            let integrated = try dynamicSidecar.integratedRootMotion(sourceSubstep: timerSubstep)
            integratedRootMotion = integrated
            animationFrameQ16 = Int32(clamping: integrated.frameQ16)
            animationEntry = integrated.clipName == "bond_eye_fire"
                ? manifest.animation.fireEntryOffset
                : manifest.animation.walkEntryOffset
        }
        let rifleCue = timerSubstep == manifest.animation.rifleCueSubstep && (nativeTick & 1) == 0

        let oldMode = mode
        let oldX = titleXQ16
        let oldTransition = transitionXQ16
        let oldWord = word
        let oldCounter = introEyeCounter
        let oldBloodIndex = bloodFrameIndex

        // Predict the next even-anchor visual endpoint without mutating the
        // current source state. Odd ticks therefore remain strict midpoints.
        let endpoint = nextEndpoint()
        let pairPhase = UInt32(nativeTick & 1)
        let renderX = pairPhase == 1 ? midpoint(oldX, endpoint.titleXQ16) : oldX
        let renderTransition = pairPhase == 1 ? midpoint(oldTransition, endpoint.transitionXQ16) : oldTransition
        let renderWord = pairPhase == 1 ? midpoint(oldWord, endpoint.word) : oldWord
        let renderCounter = pairPhase == 1 ? midpoint(oldCounter, endpoint.introEyeCounter) : oldCounter

        if pairPhase == 0 {
            commit(endpoint)
            sourceFrame &+= 1
        }

        let renderMode = oldMode
        let frame = try makeFrame(
            renderMode: renderMode,
            sourceFrame: pairPhase == 0 ? sourceFrame &- 1 : sourceFrame,
            renderX: renderX,
            renderTransition: renderTransition,
            renderWord: renderWord,
            renderCounter: renderCounter,
            rifleCue: rifleCue,
            bloodIndex: oldBloodIndex
        )
        return frame
    }

    /// Supplies the result of a decoded blood frame.  The source only exits
    /// the blood state after the model lowerer reports completion; merely
    /// having the source metadata row is insufficient.
    public mutating func acknowledgeBloodFrame(index: UInt32, complete: Bool = false) {
        bloodFrameIndex = index
        bloodFrameAvailable = true
        bloodCompletionAcknowledged = complete || index >= 41
    }

    private struct Endpoint {
        let mode: UInt32
        let titleXQ16: Int32
        let transitionXQ16: Int32
        let word: Int32
        let introEyeCounter: Int32
        let bloodFrameIndex: UInt32
    }

    private func nextEndpoint() -> Endpoint {
        var nextMode = mode
        var nextX = titleXQ16
        var nextTransition = transitionXQ16
        var nextWord = word
        var nextCounter = introEyeCounter
        var nextBlood = bloodFrameIndex
        switch mode {
        case 2:
            nextX = saturatingAdd(nextX, 6 * 65_536)
            if Int16(bitPattern: UInt16(truncatingIfNeeded: nextWord)) < 0 {
                nextWord = 200
                nextTransition = saturatingSub(nextX, 12 * 65_536)
            } else {
                nextWord = Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: nextWord &- 6)))
            }
            if nextX > 1_390 * 65_536 {
                nextMode = 3
                nextX = 1_276 * 65_536
            }
        case 3:
            // XDEC3 in title.c (NTSC) is 5.8183274f, represented in the
            // adapter's source Q16.16 domain with the same truncation used by
            // the existing C facade.
            nextX = saturatingSub(nextX, 381_310)
            if nextX <= -80 * 65_536 { nextMode = 4; nextCounter = 20 }
        case 4:
            nextCounter -= 1
            if nextCounter < 0 { nextMode = 5; nextCounter = 1; nextBlood = 0 }
        case 5:
            nextCounter -= 1
            if nextCounter == 0 {
                nextBlood &+= 1
                nextCounter = 2
            }
            if bloodCompletionAcknowledged {
                nextMode = 6
                nextWord = 0
                nextTransition = nextX
                nextCounter = 0
            }
        case 6:
            nextWord = Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: nextWord &+ 0x38e)))
            nextCounter += 1
            if nextCounter >= 108 { nextCounter = 0; nextMode = 7 }
            nextX = sineOffsetQ16(word: nextWord, transition: nextTransition)
        case 7:
            nextWord = Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: nextWord &+ 0x38e)))
            nextCounter += 8
            if nextCounter >= 247 { nextCounter = 0; nextMode = 8 }
            nextX = sineOffsetQ16(word: nextWord, transition: nextTransition)
        case 8:
            nextCounter += 1
            if nextCounter > 30 { nextCounter = 0; nextMode = 9 }
        default:
            break
        }
        return Endpoint(mode: nextMode, titleXQ16: nextX, transitionXQ16: nextTransition, word: nextWord, introEyeCounter: nextCounter, bloodFrameIndex: nextBlood)
    }

    private mutating func commit(_ endpoint: Endpoint) {
        mode = endpoint.mode
        titleXQ16 = endpoint.titleXQ16
        transitionXQ16 = endpoint.transitionXQ16
        word = endpoint.word
        introEyeCounter = endpoint.introEyeCounter
        bloodFrameIndex = endpoint.bloodFrameIndex
    }

    private func makeFrame(
        renderMode: UInt32,
        sourceFrame: UInt32,
        renderX: Int32,
        renderTransition: Int32,
        renderWord: Int32,
        renderCounter: Int32,
        rifleCue: Bool,
        bloodIndex: UInt32
    ) throws -> GoldenEyeGunbarrelFrameV6 {
        let isSight = renderMode >= 3 && renderMode <= 7
        let isBlood = renderMode == 5 && bloodFrameAvailable
        let fade: GoldenEyeGunbarrelFrameV6.Fade
        let alpha: UInt32
        switch renderMode {
        case 6: fade = .red; alpha = 180
        case 7: fade = .red; alpha = UInt32(max(0, min(247, Int(renderCounter))))
        case 8: fade = .clearBlack; alpha = 255
        default: fade = .none; alpha = 0
        }
        let parts: [GoldenEyeGunbarrelPartFrameV6] = [
            makePart(role: .body, handle: manifest.attachment.bodyModelHandle, visible: renderMode <= 7, muzzle: false),
            makePart(role: .head, handle: manifest.attachment.headModelHandle, visible: renderMode <= 7, muzzle: false),
            makePart(role: .weapon, handle: manifest.attachment.weaponModelHandle, visible: renderMode <= 7, muzzle: rifleCue)
        ]
        let poses: [GoldenEyeGunbarrelPoseV6]
        if let dynamicSidecar {
            let integrated = try (integratedRootMotion
                ?? dynamicSidecar.integratedRootMotion(sourceSubstep: timerSubstep))
            let clipName = integrated.clipName
            let clip = try dynamicSidecar.clip(named: clipName)
            let frameIndex = UInt32(max(0, integrated.frameQ16 / 65_536)) % clip.frameCount
            poses = try [
                dynamicSidecar.poses(modelHandle: manifest.attachment.bodyModelHandle, clipName: clipName, frame: frameIndex, integratedRootMotion: integrated),
                dynamicSidecar.poses(modelHandle: manifest.attachment.headModelHandle, clipName: clipName, frame: frameIndex, integratedRootMotion: integrated)
            ].flatMap { $0 }
        } else {
            poses = []
        }
        return GoldenEyeGunbarrelFrameV6(
            nativeTick: nativeTick,
            referenceTick: nativeTick / 2,
            pairPhase: UInt32(nativeTick & 1),
            sourceFrame: sourceFrame,
            mode: renderMode,
            subphase: renderMode >= 2 ? renderMode - 2 : 0,
            gunbarrelTimerSubstep: timerSubstep,
            introEyeCounter: renderCounter,
            word: renderWord,
            titleXQ16: renderX,
            transitionXQ16: renderTransition,
            bloodFrameIndex: bloodIndex,
            bloodVisible: isBlood,
            muzzleFlashVisible: rifleCue,
            // Mode 2 is the source's two-ring dot sweep.  It has no barrel
            // backdrop yet, but the generated hole mesh is visible twice.
            backgroundVisible: renderMode >= 3 && renderMode <= 7,
            holeVisible: renderMode == 2 || isSight,
            fade: fade,
            fadeAlphaQ8: alpha,
            camera: GoldenEyeGunbarrelCameraFrameV6(
                eyeQ16: manifest.camera.eyeQ16,
                directionQ16: manifest.camera.directionQ16,
                upQ16: manifest.camera.upQ16,
                fovDegreesQ16: manifest.camera.fovDegreesQ16,
                nearQ16: manifest.camera.nearQ16,
                farQ16: manifest.camera.farQ16
            ),
            parts: parts,
            poses: poses,
            rifleCue: rifleCue,
            captureReady: manifest.captureReady && bloodFrameAvailable,
            sourceManifestHash: manifest.manifestHash
        )
    }

    private func makePart(
        role: GoldenEyeGunbarrelSourceManifestV6.PartRole,
        handle: UInt32,
        visible: Bool,
        muzzle: Bool
    ) -> GoldenEyeGunbarrelPartFrameV6 {
        let entry = role == .weapon && timerSubstep >= manifest.animation.animationStartSubstep
            ? manifest.animation.fireEntryOffset : manifest.animation.walkEntryOffset
        var hash: UInt64 = 1_469_598_103_934_665_603
        hash ^= UInt64(handle); hash &*= 1_099_511_628_211
        hash ^= UInt64(bitPattern: Int64(animationFrameQ16)); hash &*= 1_099_511_628_211
        hash ^= UInt64(entry); hash &*= 1_099_511_628_211
        return GoldenEyeGunbarrelPartFrameV6(
            role: role,
            modelHandle: handle,
            visible: visible,
            attachmentNode: role == .weapon ? manifest.attachment.gunParentSwitch : 0,
            muzzleFlashVisible: muzzle,
            animationEntryOffset: animationEntry,
            animationFrameQ16: animationFrameQ16,
            poseHash: hash
        )
    }

    private func sineOffsetQ16(word: Int32, transition: Int32) -> Int32 {
        let radians = Double(Int16(bitPattern: UInt16(truncatingIfNeeded: word))) * Double.pi / 32_768.0
        let delta = Int32((sin(radians) * 64.0 * 65_536.0).rounded())
        return saturatingAdd(transition, delta)
    }

    private func midpoint(_ a: Int32, _ b: Int32) -> Int32 {
        Int32((Int64(a) + Int64(b)) / 2)
    }

    private func saturatingAdd(_ a: Int32, _ b: Int32) -> Int32 {
        let value = Int64(a) + Int64(b)
        return Int32(clamping: value)
    }

    private func saturatingSub(_ a: Int32, _ b: Int32) -> Int32 {
        let value = Int64(a) - Int64(b)
        return Int32(clamping: value)
    }
}

private extension Int32 {
    init(clamping value: Int64) {
        self = Int32(Swift.max(Int64(Int32.min), Swift.min(Int64(Int32.max), value)))
    }
}

private func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
    digest.map { String(format: "%02x", $0) }.joined()
}
