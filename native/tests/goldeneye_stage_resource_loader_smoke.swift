import Foundation

@main
struct GoldenEyeStageResourceLoaderSmoke {
    static func main() throws {
        let rootPath = CommandLine.arguments.dropFirst().first
            ?? ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_STAGE_ASSET_ROOT"]
            ?? "build/native/stage-assets"
        let catalog = try GoldenEyeStageAssetCatalog.load(
            stageAssetRoot: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        let loader = GoldenEyeStageResourceLoader(catalog: catalog)

        let partial = try loader.copyPackets(firstPacket: 0, capacity: 2)
        precondition(partial.status == UInt32(GE_STATUS_INVALID_SIZE))
        precondition(partial.packets.count == 2)
        precondition(partial.diagnostic?.code == UInt32(GE_STAGE_V5_DIAG_COPY_OUT))
        precondition(partial.diagnostic?.detail0 == UInt32(GE_STAGE_V5_RESOURCE_PACKET_COUNT))
        precondition(partial.diagnostic?.detail1 == 2)

        let packets = try loader.copyPackets(
            firstPacket: 0,
            capacity: Int(GE_STAGE_V5_RESOURCE_PACKET_COUNT)
        )
        precondition(packets.status == UInt32(GE_STATUS_OK))
        precondition(packets.packets.count == 21)
        precondition(packets.diagnostic == nil)
        precondition(packets.packets.first?.packetIndex == 0)
        precondition(packets.packets.last?.packetIndex == 20)

        let arenaBytes = catalog.stages
            .flatMap(\.resources)
            .reduce(UInt32(0)) { partial, resource in
                partial + resource.decodedBytes
            }
        let views = try loader.views(decodedArenaBase: 4096, decodedArenaBytes: arenaBytes + 4096)
        precondition(views.count == 21)
        precondition(views.first?.decodedBaseOffset == 4096)
        precondition(views.allSatisfy { $0.metadataHash != 0 })
        precondition(views.allSatisfy { $0.flags == UInt32(GE_STAGE_V5_RESOURCE_FLAG_MASK) })
        precondition(views.last?.decodedBaseOffset ?? 0 > views.first?.decodedBaseOffset ?? 0)

        do {
            _ = try loader.views(decodedArenaBase: 4096, decodedArenaBytes: arenaBytes - 1)
            preconditionFailure("undersized decoded arena unexpectedly accepted")
        } catch GoldenEyeStageResourceLoaderError.arenaOverflow {
        }

        let repeatViews = try loader.views(decodedArenaBase: 4096, decodedArenaBytes: arenaBytes + 4096)
        precondition(repeatViews == views)
        print(
            "goldeneye_stage_resource_loader_smoke: PASS " +
                "packets=21 views=21 partial_status=\(partial.status) " +
                "first_base=\(views[0].decodedBaseOffset) last_base=\(views[20].decodedBaseOffset)"
        )
    }
}
