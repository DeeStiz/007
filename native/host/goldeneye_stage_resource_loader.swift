import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

public enum GoldenEyeStageResourceLoaderError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidCapacity
    case copyOutFailed(UInt32, String)
    case packetCountMismatch(UInt32)
    case unknownPacket(UInt32, UInt32)
    case cCatalogStatus(UInt32, UInt32)
    case viewFailed(UInt32, UInt32, UInt32, String)
    case arenaOverflow

    public var description: String {
        switch self {
        case .invalidCapacity:
            return "stage resource copy-out capacity must be positive"
        case let .copyOutFailed(status, message):
            return "stage resource copy-out failed with status \(status): \(message)"
        case let .packetCountMismatch(count):
            return "stage resource copy-out returned \(count) packets"
        case let .unknownPacket(stageID, kind):
            return "stage resource packet \(stageID)/\(kind) is not in the catalog"
        case let .cCatalogStatus(stageID, status):
            return "stage resource C catalog lookup \(stageID) failed with status \(status)"
        case let .viewFailed(stageID, kind, status, message):
            return "stage resource view \(stageID)/\(kind) failed with status \(status): \(message)"
        case .arenaOverflow:
            return "stage decoded arena offset overflowed the fixed-width range"
        }
    }
}

public struct GoldenEyeStageResourceCopyOutDiagnostic: Sendable, Equatable {
    public let code: UInt32
    public let flags: UInt32
    public let stageID: UInt32
    public let resourceKind: UInt32
    public let byteOffset: UInt32
    public let detail0: UInt32
    public let detail1: UInt32
    public let message: String
}

public struct GoldenEyeStageResourcePacket: Sendable, Equatable {
    public let packetIndex: UInt32
    public let stageID: UInt32
    public let stageName: String
    public let kind: GoldenEyeStageAssetKind
    public let resourceName: String
    public let assetHandle: UInt32
    public let compression: UInt32
    public let flags: UInt32
    public let sourceOffset: UInt32
    public let sourceBytes: UInt32
    public let decodedBytes: UInt32
    public let metadataHash: UInt64
}

public struct GoldenEyeStageResourceCopyOutResult: Sendable, Equatable {
    public let status: UInt32
    public let packets: [GoldenEyeStageResourcePacket]
    public let diagnostic: GoldenEyeStageResourceCopyOutDiagnostic?
}

public struct GoldenEyeStageResourceView: Sendable, Equatable {
    public let packetIndex: UInt32
    public let stageID: UInt32
    public let stageName: String
    public let kind: GoldenEyeStageAssetKind
    public let resourceName: String
    public let assetHandle: UInt32
    public let compression: UInt32
    public let flags: UInt32
    public let decodedBaseOffset: UInt32
    public let decodedBytes: UInt32
    public let sourceOffset: UInt32
    public let sourceBytes: UInt32
    public let metadataHash: UInt64
}

/// Metadata-only stage loader. It assigns deterministic decoded-arena offsets
/// in C catalog packet order; it does not load payload bytes, start gameplay,
/// or create renderer resources.
public struct GoldenEyeStageResourceLoader: Sendable {
    public let catalog: GoldenEyeStageAssetCatalog

    public init(catalog: GoldenEyeStageAssetCatalog) {
        self.catalog = catalog
    }

    public func copyPackets(
        firstPacket: UInt32 = 0,
        capacity: Int
    ) throws -> GoldenEyeStageResourceCopyOutResult {
        guard capacity > 0 else {
            throw GoldenEyeStageResourceLoaderError.invalidCapacity
        }
        var cPackets = [GEStageResourcePacketV5](
            repeating: GEStageResourcePacketV5(),
            count: capacity
        )
        var packetCount: UInt32 = 0
        var diagnostic = GEStageDiagnosticV5()
        let status = cPackets.withUnsafeMutableBufferPointer { buffer -> UInt32 in
            UInt32(ge_stage_v5_copy_resource_packets(
                firstPacket,
                UInt32(capacity),
                buffer.baseAddress,
                &packetCount,
                &diagnostic
            ))
        }
        let converted = cPackets.prefix(Int(packetCount)).map { packet in
            packetValue(packet)
        }
        let diagnosticValue = diagnosticValue(diagnostic)
        if status != UInt32(GE_STATUS_OK) &&
            status != UInt32(GE_STATUS_INVALID_SIZE) {
            throw GoldenEyeStageResourceLoaderError.copyOutFailed(
                status,
                diagnosticValue?.message ?? "no diagnostic"
            )
        }
        return GoldenEyeStageResourceCopyOutResult(
            status: status,
            packets: converted,
            diagnostic: diagnosticValue
        )
    }

    public func views(
        decodedArenaBase: UInt32 = 0,
        decodedArenaBytes: UInt32
    ) throws -> [GoldenEyeStageResourceView] {
        let result = try copyPackets(
            firstPacket: 0,
            capacity: Int(GE_STAGE_V5_RESOURCE_PACKET_COUNT)
        )
        guard result.status == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeStageResourceLoaderError.copyOutFailed(
                result.status,
                result.diagnostic?.message ?? "resource packet copy-out was truncated"
            )
        }
        guard result.packets.count == Int(GE_STAGE_V5_RESOURCE_PACKET_COUNT) else {
            throw GoldenEyeStageResourceLoaderError.packetCountMismatch(
                UInt32(result.packets.count)
            )
        }

        var views: [GoldenEyeStageResourceView] = []
        views.reserveCapacity(result.packets.count)
        var cursor = decodedArenaBase
        for packet in result.packets {
            let used = cursor >= decodedArenaBase ? cursor - decodedArenaBase : UInt32.max
            guard used <= decodedArenaBytes,
                  packet.decodedBytes <= decodedArenaBytes - used,
                  cursor <= UInt32.max - packet.decodedBytes else {
                throw GoldenEyeStageResourceLoaderError.arenaOverflow
            }

            var entry = GEStageCatalogEntryV5()
            let catalogStatus = UInt32(ge_stage_v5_find_stage(packet.stageID, &entry))
            guard catalogStatus == UInt32(GE_STATUS_OK) else {
                throw GoldenEyeStageResourceLoaderError.cCatalogStatus(
                    packet.stageID,
                    catalogStatus
                )
            }
            let resourceKind = packet.kind.cKindForLoader
            var cResource = resourceValue(for: resourceKind, entry: entry)
            var cView = GEStageResourceViewV5()
            var cDiagnostic = GEStageDiagnosticV5()
            let viewStatus = UInt32(ge_stage_v5_make_resource_view(
                &cResource,
                cursor,
                decodedArenaBytes - used,
                &cView,
                &cDiagnostic
            ))
            guard viewStatus == UInt32(GE_STATUS_OK) else {
                throw GoldenEyeStageResourceLoaderError.viewFailed(
                    packet.stageID,
                    resourceKind,
                    viewStatus,
                    diagnosticValue(cDiagnostic)?.message ?? "no diagnostic"
                )
            }
            guard UInt32(ge_stage_v5_validate_resource_view(&cView)) == UInt32(GE_STATUS_OK) else {
                throw GoldenEyeStageResourceLoaderError.viewFailed(
                    packet.stageID,
                    resourceKind,
                    UInt32(GE_STATUS_MALFORMED_STREAM),
                    "C resource view validation failed after construction"
                )
            }
            views.append(
                GoldenEyeStageResourceView(
                    packetIndex: packet.packetIndex,
                    stageID: cView.stage_id,
                    stageName: packet.stageName,
                    kind: packet.kind,
                    resourceName: packet.resourceName,
                    assetHandle: cView.asset_handle,
                    compression: cView.compression,
                    flags: cView.flags,
                    decodedBaseOffset: cView.decoded_base_offset,
                    decodedBytes: cView.decoded_bytes,
                    sourceOffset: cView.source_offset,
                    sourceBytes: cView.source_bytes,
                    metadataHash: cView.metadata_hash
                )
            )
            cursor += packet.decodedBytes
        }
        return views
    }

    private func packetValue(_ packet: GEStageResourcePacketV5) -> GoldenEyeStageResourcePacket {
        let kind = GoldenEyeStageAssetKind.allCases.first {
            $0.cKindForLoader == packet.resource_kind
        } ?? .background
        let stage = catalog.stages.first { $0.stageID == packet.stage_id }
        return GoldenEyeStageResourcePacket(
            packetIndex: packet.packet_index,
            stageID: packet.stage_id,
            stageName: stage?.stageName ?? "<unknown>",
            kind: kind,
            resourceName: cString(packet.resource_name, capacity: Int(GE_STAGE_V5_RESOURCE_NAME_BYTES)),
            assetHandle: packet.asset_handle,
            compression: packet.compression,
            flags: packet.flags,
            sourceOffset: packet.source_offset,
            sourceBytes: packet.source_bytes,
            decodedBytes: packet.decoded_bytes,
            metadataHash: packet.metadata_hash
        )
    }

    private func resourceValue(
        for resourceKind: UInt32,
        entry: GEStageCatalogEntryV5
    ) -> GEStageResourceV5 {
        switch resourceKind {
        case UInt32(GE_STAGE_V5_RESOURCE_BACKGROUND): return entry.background
        case UInt32(GE_STAGE_V5_RESOURCE_STAN): return entry.stan
        default: return entry.setup
        }
    }

    private func diagnosticValue(_ diagnostic: GEStageDiagnosticV5) -> GoldenEyeStageResourceCopyOutDiagnostic? {
        guard diagnostic.code != UInt32(GE_STAGE_V5_DIAG_NONE) else { return nil }
        return GoldenEyeStageResourceCopyOutDiagnostic(
            code: diagnostic.code,
            flags: diagnostic.flags,
            stageID: diagnostic.stage_id,
            resourceKind: diagnostic.resource_kind,
            byteOffset: diagnostic.byte_offset,
            detail0: diagnostic.detail0,
            detail1: diagnostic.detail1,
            message: cString(diagnostic.message, capacity: 96)
        )
    }

    private func cString<T>(_ tuple: T, capacity: Int) -> String {
        var value = tuple
        return withUnsafePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { cStringPointer in
                String(cString: cStringPointer)
            }
        }
    }
}

private extension GoldenEyeStageAssetKind {
    var cKindForLoader: UInt32 {
        switch self {
        case .background: return UInt32(GE_STAGE_V5_RESOURCE_BACKGROUND)
        case .stan: return UInt32(GE_STAGE_V5_RESOURCE_STAN)
        case .setup: return UInt32(GE_STAGE_V5_RESOURCE_SETUP)
        }
    }
}
