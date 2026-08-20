import Foundation

@available(macOS 26.0, *)
@main
struct GoldenEyeGoldenEyeLogoFrameV6Smoke {
    static func main() throws {
        let root = URL(
            fileURLWithPath: CommandLine.arguments.dropFirst().first
                ?? "build/native/source-frontend-v6",
            isDirectory: true
        )
        let odd = try GoldenEyeGoldenEyeLogoFrameV6.build(
            rootURL: root,
            nativeTick: GoldenEyeGoldenEyeLogoFrameV6.routeGoldenEyeNativeTick + 1
        )
        let even = try GoldenEyeGoldenEyeLogoFrameV6.build(
            rootURL: root,
            nativeTick: GoldenEyeGoldenEyeLogoFrameV6.routeGoldenEyeNativeTick + 2
        )
        precondition(odd.source.nativeTick & 1 == 1)
        precondition(even.source.nativeTick & 1 == 0)
        precondition(odd.source.sourceTimer == 0)
        precondition(even.source.sourceTimer == 1)
        precondition(odd.source.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE))
        precondition(even.source.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE))
        precondition(odd.scene.sourceCommandWordHash == even.scene.sourceCommandWordHash)
        precondition(odd.scene.snapshot.drawCommands.count > 0)
        precondition(even.scene.snapshot.drawCommands.count == odd.scene.snapshot.drawCommands.count)
        precondition(odd.omittedDegenerateTriangles.map(\.packetByteOffset) == [0x290, 0x400])
        precondition(odd.omittedDegenerateTriangles.map(\.sourceCommandIndex) == [80, 126])
        precondition(odd.omittedDegenerateTriangles.allSatisfy {
            $0.sourceVertexA == 0 && $0.sourceVertexB == 0 && $0.sourceVertexC == 0
        })
        precondition(even.omittedDegenerateTriangles == odd.omittedDegenerateTriangles)
        precondition(odd.frameHash != even.frameHash)
        precondition(odd.matrixFrame.frameHash != even.matrixFrame.frameHash)
        precondition(odd.materialTextureHandles.count > 0)
        precondition(Set(odd.materialTextureHandles) == Set(odd.modelTextureHandles))
        precondition(!odd.textureSetups.isEmpty)
        precondition(odd.textureSetups.contains { $0.resourceHandle == odd.modelTextureHandles[0] })
        precondition(odd.textureSetups.contains { $0.resourceHandle == odd.modelTextureHandles[1] })
        precondition(odd.textureSetups == even.textureSetups)
        precondition(odd.sourceMipCount == GoldenEyeGoldenEyeLogoFrameV6.sourceMipCount)
        print("goldeneye-logo-frame-v6: odd=\(odd.scene.packetCommandCount)/\(odd.scene.triangleCount)/\(odd.scene.snapshot.drawCommands.count) even=\(even.scene.packetCommandCount)/\(even.scene.triangleCount)/\(even.scene.snapshot.drawCommands.count) materials=\(odd.materialTextureHandles) omittedDegenerate=\(odd.omittedDegenerateTriangles.map { String(format: "0x%03x", $0.packetByteOffset) }) frameHashes=\(odd.frameHash)/\(even.frameHash) PASS")
    }
}
