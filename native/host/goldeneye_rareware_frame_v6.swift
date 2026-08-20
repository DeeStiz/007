import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Source-owned Rareware logo frame data.
///
/// Rareware is not a model graph.  The source constructor uploads a dedicated
/// segment and submits three display-list passes in a fixed order.  Keeping
/// this contract separate from the graph compiler prevents a graph fallback
/// from claiming the LOD/FRACTION pass is presentable.  Every field below is a
/// copied fixed-width value; no source address, ROM offset, or Metal object is
/// retained.
struct GoldenEyeRarewareFrameV6: Sendable, Equatable {
    static let modelName = "rarewarelogo"
    // GESM handles are deterministic sidecar handles (FNV-1a of
    // "model:rarewarelogo").  The source screen's model identity remains 1
    // in the independent reference fixture; it is not reused as a packet
    // handle.
    static let expectedModelHandle: UInt32 = 0xc93f_b7e2
    static let expectedDisplayListCount = 9
    static let expectedCommandCount = 389
    static let expectedVertexCount = 397
    static let expectedTextureCount = 6
    static let expectedMipCount = 26
    static let expectedMipChainCount = 4
    static let expectedTriangleCount: UInt32 = 268
    static let expectedSourceCommandHash: UInt64 = 0xef6d_7f72_78f9_f74a
    static let rarewareSFXAssetID: UInt32 = 258

    enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case invalidInput(String)
        case sourceDrift(String)
        case unsupportedVisibleCommand(String)
        case malformedTiming(String)

        var description: String {
            switch self {
            case .invalidInput(let detail): return "Rareware V6 invalid input: \(detail)"
            case .sourceDrift(let detail): return "Rareware V6 source drift: \(detail)"
            case .unsupportedVisibleCommand(let detail):
                return "Rareware V6 unsupported visible command: \(detail)"
            case .malformedTiming(let detail): return "Rareware V6 malformed timing: \(detail)"
            }
        }
    }

    struct Pass: Sendable, Equatable {
        let displayListID: UInt32
        let commandStart: UInt32
        let commandCount: UInt32
        let triangleCount: UInt32
        let cycleCount: UInt32
        let geometryMode: UInt32
        let textureIndices: [UInt32]
        let mipLODEnabled: Bool
        let hasLODGradient: Bool
        let sourceWordHash: UInt64
    }

    struct Projection: Sendable, Equatable {
        let fovyDegreesQ16: Int32
        let aspectQ16: Int32
        let nearQ16: Int32
        let farQ16: Int32
        let cameraXQ16: Int32
        let cameraYQ16: Int32
        let cameraZQ16: Int32
        let targetXQ16: Int32
        let targetYQ16: Int32
        let targetZQ16: Int32
        let upXQ16: Int32
        let upYQ16: Int32
        let upZQ16: Int32
    }

    let nativeTick: UInt64
    let referenceTick: UInt64
    let sourceTimer: UInt32
    let pairPhase: UInt32
    let refreshPAL: Bool
    let rotationDegreesQ16: Int32
    let fadeAlpha: UInt8
    let transitionReady: Bool
    let projection: Projection
    let passes: [Pass]
    let textureHandles: [UInt32]
    let mipLevelsByTexture: [UInt32]
    let sourceCommandHash: UInt64
    let sourceTriangleCount: UInt32
    let sourceSFXAssetID: UInt32
    let frameHash: UInt64

    var sourceCommandCount: UInt32 { UInt32(Self.expectedCommandCount) }

    /// Build one source-owned Rareware frame from the guarded GESM packet.
    ///
    /// NTSC is the production target.  PAL timing is retained as an explicit
    /// input because the source has a separate rotation increment and fade
    /// denominator; it is never silently selected by the renderer.
    static func make(
        model: GoldenEyeSourceModelV6,
        nativeTick: UInt64,
        referenceTick: UInt64,
        sourceTimer: UInt32,
        pairPhase: UInt32,
        refreshPAL: Bool = false
    ) throws -> GoldenEyeRarewareFrameV6 {
        guard nativeTick > 0, pairPhase <= 1 else {
            throw Error.invalidInput("native tick/pair phase")
        }
        guard model.header.modelHandle == expectedModelHandle else {
            throw Error.sourceDrift("model handle \(model.header.modelHandle)")
        }
        guard model.header.counts.displayLists == expectedDisplayListCount,
              model.header.counts.commands == expectedCommandCount,
              model.header.counts.vertices == expectedVertexCount,
              model.header.counts.textures == expectedTextureCount,
              model.header.counts.mips == expectedMipCount,
              model.header.counts.tluts == 0 else {
            throw Error.sourceDrift(
                "counts lists=\(model.header.counts.displayLists) commands=\(model.header.counts.commands) " +
                    "vertices=\(model.header.counts.vertices) textures=\(model.header.counts.textures) " +
                    "mips=\(model.header.counts.mips) tluts=\(model.header.counts.tluts)"
            )
        }

        let expectedLists: [(id: Int, start: Int, count: Int, name: String, triangles: UInt32)] = [
            (4, 4, 25, "D_020043E8", 18),
            (5, 29, 85, "DL_RAREWARETEXT", 8),
            (6, 114, 273, "D_02004758", 242),
        ]
        for expected in expectedLists {
            guard expected.id < model.displayLists.count else {
                throw Error.sourceDrift("missing display list \(expected.id)")
            }
            let list = model.displayLists[expected.id]
            let expectedAnonymousRarewareText = expected.id == 5 &&
                list.handle == 0xa538_8e8d
            guard Int(list.commandStart) == expected.start,
                  Int(list.commandCount) == expected.count,
                  list.name == expected.name || expectedAnonymousRarewareText else {
                throw Error.sourceDrift(
                    "display list \(expected.id) = \(list.name) [\(list.commandStart),\(list.commandCount)]"
                )
            }
        }

        var sourceCommandHash: UInt64 = 1_469_598_103_934_665_603
        for commandIndex in model.commands.indices {
            guard let encoded = GESourceModelCompilerV6.encodedWords(
                model: model,
                commandIndex: commandIndex
            ) else {
                throw Error.unsupportedVisibleCommand("command \(commandIndex) cannot be encoded")
            }
            sourceCommandHash = hash(sourceCommandHash, UInt64(encoded.word0))
            sourceCommandHash = hash(sourceCommandHash, UInt64(encoded.word1))
            sourceCommandHash = hash(sourceCommandHash, UInt64(commandIndex))
        }

        let pass0 = try makePass(
            model: model,
            listID: 4,
            expectedStart: 4,
            expectedCount: 25,
            expectedTriangles: 18,
            expectedCycleCount: 1,
            expectedGeometryMode: 0x0006_0000,
            expectedTextureIndices: [4],
            requireLOD: false,
            requireLODGradient: false
        )
        let pass1 = try makePass(
            model: model,
            listID: 5,
            expectedStart: 29,
            expectedCount: 85,
            expectedTriangles: 8,
            expectedCycleCount: 2,
            expectedGeometryMode: 0,
            expectedTextureIndices: [0, 1, 2, 3],
            requireLOD: true,
            requireLODGradient: true
        )
        let pass2 = try makePass(
            model: model,
            listID: 6,
            expectedStart: 114,
            expectedCount: 273,
            expectedTriangles: 242,
            expectedCycleCount: 1,
            expectedGeometryMode: 0x0006_0000,
            expectedTextureIndices: [5],
            requireLOD: false,
            requireLODGradient: false
        )

        guard model.textures.enumerated().allSatisfy({ index, texture in
            texture.index == UInt32(index) && texture.width == 32 && texture.height == 32 &&
                texture.depth == 2 && texture.mipCount == (index < 4 ? 6 : 1)
        }) else {
            throw Error.sourceDrift("texture dimensions/depth/mip declarations")
        }
        let mipLevels = model.textures.map(\.mipCount)
        guard mipLevels.filter({ $0 == 6 }).count == expectedMipChainCount else {
            throw Error.sourceDrift("expected four six-level mip chains")
        }

        let denominator: Int64 = refreshPAL ? 58 : 70
        let fadeSub: Int64 = refreshPAL ? 33_915 : 40_800
        let firstCounter: UInt32 = refreshPAL ? 216 : 260
        let secondCounter: UInt32 = refreshPAL ? 241 : 290
        let counter = Int64(sourceTimer)
        let fadeIn = clamp((counter * 255) / denominator, low: 0, high: 255)
        let fadeOut = clamp(255 - ((counter * 255 - fadeSub) / denominator), low: 0, high: 255)
        let fade = (fadeIn * fadeOut) / 255
        guard fade >= 0, fade <= 255 else {
            throw Error.malformedTiming("fade alpha out of range")
        }
        let transitionReady = sourceTimer >= secondCounter
        // The source compares against the pre-increment counter after the
        // display list has been emitted.  The first threshold advances the
        // mode only after the current frame; the second threshold is the
        // externally visible route boundary.
        guard sourceTimer < UInt32.max || transitionReady else {
            throw Error.malformedTiming("counter overflow")
        }
        _ = firstCounter

        let rotationStepQ16: Int64 = refreshPAL ? 2_400 * 65_536 / 1_000 : 2 * 65_536
        let halfStepQ16 = pairPhase == 1 ? rotationStepQ16 / 2 : 0
        let rotation = (-40 * 65_536) + Int64(sourceTimer) * rotationStepQ16 + halfStepQ16
        guard rotation >= Int64(Int32.min), rotation <= Int64(Int32.max) else {
            throw Error.malformedTiming("rotation overflow")
        }

        let projection = Projection(
            fovyDegreesQ16: 60 * 65_536,
            aspectQ16: (4 * 65_536) / 3,
            nearQ16: 100 * 65_536,
            farQ16: 5_000 * 65_536,
            cameraXQ16: 0,
            cameraYQ16: 0,
            cameraZQ16: 880 * 65_536,
            targetXQ16: 0,
            targetYQ16: 0,
            targetZQ16: 879 * 65_536,
            upXQ16: 0,
            upYQ16: 65_536,
            upZQ16: 0
        )

        var frameHash = sourceCommandHash
        frameHash = hash(frameHash, nativeTick)
        frameHash = hash(frameHash, referenceTick)
        frameHash = hash(frameHash, UInt64(sourceTimer))
        frameHash = hash(frameHash, UInt64(pairPhase))
        frameHash = hash(frameHash, UInt64(UInt32(bitPattern: Int32(rotation))))
        frameHash = hash(frameHash, UInt64(fade))
        frameHash = hash(frameHash, transitionReady ? 1 : 0)

        return GoldenEyeRarewareFrameV6(
            nativeTick: nativeTick,
            referenceTick: referenceTick,
            sourceTimer: sourceTimer,
            pairPhase: pairPhase,
            refreshPAL: refreshPAL,
            rotationDegreesQ16: Int32(rotation),
            fadeAlpha: UInt8(fade),
            transitionReady: transitionReady,
            projection: projection,
            passes: [pass0, pass1, pass2],
            textureHandles: model.textures.map(\.resourceHandle),
            mipLevelsByTexture: mipLevels,
            sourceCommandHash: sourceCommandHash,
            sourceTriangleCount: Self.expectedTriangleCount,
            sourceSFXAssetID: rarewareSFXAssetID,
            frameHash: frameHash == 0 ? 1 : frameHash
        )
    }

    private static func makePass(
        model: GoldenEyeSourceModelV6,
        listID: Int,
        expectedStart: Int,
        expectedCount: Int,
        expectedTriangles: UInt32,
        expectedCycleCount: UInt32,
        expectedGeometryMode: UInt32,
        expectedTextureIndices: [UInt32],
        requireLOD: Bool,
        requireLODGradient: Bool
    ) throws -> Pass {
        let list = model.displayLists[listID]
        let start = Int(list.commandStart)
        let end = start + Int(list.commandCount)
        guard start == expectedStart, end == expectedStart + expectedCount else {
            throw Error.sourceDrift("pass \(listID) command range")
        }
        let commands = Array(model.commands[start..<end])
        let triangles = commands.reduce(into: UInt32(0)) { count, command in
            if command.semantic.hasPrefix("gsSP1Triangle") { count += 1 }
            else if command.semantic.hasPrefix("gsSP2Triangles") { count += 2 }
            else if command.semantic.hasPrefix("gsSP4Triangles") { count += 4 }
        }
        guard triangles == expectedTriangles else {
            throw Error.sourceDrift("pass \(listID) triangles \(triangles)")
        }
        let cycleCount: UInt32
        if commands.contains(where: { $0.semantic.hasPrefix("gsDPSetCycleType(G_CYC_2CYCLE") }) {
            cycleCount = 2
        } else if commands.contains(where: { $0.semantic.hasPrefix("gsDPSetCycleType(G_CYC_1CYCLE") }) {
            cycleCount = 1
        } else {
            throw Error.sourceDrift("pass \(listID) has no cycle declaration")
        }
        guard cycleCount == expectedCycleCount else {
            throw Error.sourceDrift("pass \(listID) cycle \(cycleCount)")
        }
        let geometry: UInt32
        if let geometryIndex = (start..<end).first(where: {
            model.commands[$0].semantic.hasPrefix("gsSPSetGeometryMode")
        }) {
            guard let value = model.tokens(for: geometryIndex).first else {
                throw Error.sourceDrift("pass \(listID) geometry token")
            }
            let semantic = model.commands[geometryIndex].semantic
            if semantic.contains("G_LIGHTING") && semantic.contains("G_TEXTURE_GEN") {
                geometry = 0x0006_0000
            } else {
                geometry = compact(value)
            }
        } else if commands.contains(where: { $0.semantic.hasPrefix("gsSPClearGeometryMode") }) {
            geometry = 0
        } else {
            throw Error.sourceDrift("pass \(listID) geometry mode")
        }
        guard geometry == expectedGeometryMode else {
            throw Error.sourceDrift("pass \(listID) geometry 0x\(String(geometry, radix: 16))")
        }
        let hasLOD = commands.contains(where: { $0.semantic.hasPrefix("gsDPSetTextureLOD(G_TL_LOD") })
        let hasGradient = commands.contains(where: {
            $0.semantic.contains("LOD_FRACTION") && $0.semantic.hasPrefix("gsDPSetCombineLERP")
        })
        guard hasLOD == requireLOD, hasGradient == requireLODGradient else {
            throw Error.sourceDrift("pass \(listID) LOD state")
        }

        var textureIndices: [UInt32] = []
        for commandIndex in start..<end where model.commands[commandIndex].semantic.hasPrefix("gsDPSetTextureImage") {
            guard let token = model.tokens(for: commandIndex).last,
                  case .handle(_, let handle) = tokenValue(token) else {
                throw Error.sourceDrift("pass \(listID) texture image handle")
            }
            guard let texture = model.textures.first(where: { $0.resourceHandle == handle }) else {
                throw Error.sourceDrift("pass \(listID) texture handle 0x\(String(handle, radix: 16))")
            }
            if !textureIndices.contains(texture.index) { textureIndices.append(texture.index) }
        }
        if listID == 4 { textureIndices = [4] }
        if listID == 6 { textureIndices = [5] }
        guard textureIndices == expectedTextureIndices else {
            throw Error.sourceDrift("pass \(listID) textures \(textureIndices)")
        }
        var wordHash: UInt64 = 1_469_598_103_934_665_603
        for commandIndex in start..<end {
            guard let words = GESourceModelCompilerV6.encodedWords(model: model, commandIndex: commandIndex) else {
                throw Error.unsupportedVisibleCommand("pass \(listID) command \(commandIndex)")
            }
            wordHash = hash(wordHash, UInt64(words.word0))
            wordHash = hash(wordHash, UInt64(words.word1))
        }
        return Pass(
            displayListID: UInt32(listID),
            commandStart: UInt32(start),
            commandCount: UInt32(expectedCount),
            triangleCount: triangles,
            cycleCount: cycleCount,
            geometryMode: geometry,
            textureIndices: textureIndices,
            mipLODEnabled: hasLOD,
            hasLODGradient: hasGradient,
            sourceWordHash: wordHash
        )
    }

    private static func tokenValue(_ token: GoldenEyeSourceModelV6.Token) -> GoldenEyeSourceModelV6.TokenValue {
        if token.text == "null" { return .null }
        if token.text == "true" { return .boolean(true) }
        if token.text == "false" { return .boolean(false) }
        if let integer = Int64(token.text) { return .integer(integer) }
        if token.text.hasPrefix("0x"), let integer = Int64(token.text.dropFirst(2), radix: 16) {
            return .integer(integer)
        }
        if token.text.hasPrefix("handle("), token.text.count > 8 {
            let body = token.text.dropFirst(7).dropLast()
            let pieces = body.split(separator: ",")
            if pieces.count == 2, let value = UInt32(pieces[1].dropFirst(2), radix: 16) {
                return .handle(kind: .opaque, value: value)
            }
        }
        return .constant(name: token.text, value: token.encodedValue)
    }

    private static func compact(_ token: GoldenEyeSourceModelV6.Token) -> UInt32 {
        switch tokenValue(token) {
        case .integer(let value): return UInt32(truncatingIfNeeded: value)
        case .constant(_, let value): return value
        case .handle(_, let value): return value
        case .null: return GoldenEyeSourceModelV6.nullHandle
        case .boolean(let value): return value ? 1 : 0
        }
    }

    private static func clamp(_ value: Int64, low: Int64, high: Int64) -> Int64 {
        min(high, max(low, value))
    }

    private static func hash(_ seed: UInt64, _ value: UInt64) -> UInt64 {
        var result = seed ^ value
        result &*= 1_099_511_628_211
        return result
    }

}

/// Source-ordered geometry emitted by the three Rareware display-list passes.
/// Each triangle owns copied vertex values so later `gsSPVertex` cache loads
/// cannot rewrite an earlier triangle.  The packet retains the source S/T
/// integers; the texture-coordinate lowerer applies the source tile state at
/// the final render boundary.
struct GoldenEyeRarewareGeometryV6: Sendable, Equatable {
    struct Vertex: Sendable, Equatable {
        let sourceIndex: UInt32
        let x: Int32
        let y: Int32
        let z: Int32
        let s: Int32
        let t: Int32
        let nx: Int8
        let ny: Int8
        let nz: Int8
        let rgba: UInt32
    }

    struct Triangle: Sendable, Equatable {
        let passIndex: UInt32
        let textureIndex: UInt32
        let sourceCommandOffset: UInt32
        let vertexStart: UInt32
    }

    let vertices: [Vertex]
    let triangles: [Triangle]
    let sourceCommandHash: UInt64
    let geometryHash: UInt64

    static func make(
        model: GoldenEyeSourceModelV6,
        frame: GoldenEyeRarewareFrameV6
    ) throws -> GoldenEyeRarewareGeometryV6 {
        guard frame.passes.count == 3 else {
            throw GoldenEyeRarewareFrameV6.Error.invalidInput("Rareware pass count")
        }
        var groups: [UInt32: [GoldenEyeSourceModelV6.Vertex]] = [:]
        for vertex in model.vertices {
            groups[vertex.groupHandle, default: []].append(vertex)
        }
        for key in groups.keys {
            groups[key]?.sort { $0.id < $1.id }
        }

        var cache = Array<GoldenEyeSourceModelV6.Vertex?>(repeating: nil, count: 64)
        var vertices: [Vertex] = []
        var triangles: [Triangle] = []
        vertices.reserveCapacity(Int(frame.sourceTriangleCount) * 3)
        triangles.reserveCapacity(Int(frame.sourceTriangleCount))

        for (passIndex, pass) in frame.passes.enumerated() {
            let start = Int(pass.commandStart)
            let end = start + Int(pass.commandCount)
            var activeTextureIndex: UInt32 = pass.textureIndices.first ?? 0
            for commandIndex in start..<end {
                let command = model.commands[commandIndex]
                if command.semantic.hasPrefix("gsDPSetTextureImage") {
                    guard let token = model.tokens(for: commandIndex).last,
                          case .handle(_, let handle) = tokenValue(token),
                          let texture = model.textures.first(where: { $0.resourceHandle == handle }) else {
                        throw GoldenEyeRarewareFrameV6.Error.sourceDrift(
                            "geometry texture image at command \(commandIndex)"
                        )
                    }
                    activeTextureIndex = texture.index
                }
                if command.semantic.hasPrefix("gsSPVertex") {
                    let tokens = Array(model.tokens(for: commandIndex))
                    guard tokens.count == 3,
                          case .handle(_, let groupHandle) = tokenValue(tokens[0]) else {
                        throw GoldenEyeRarewareFrameV6.Error.sourceDrift(
                            "geometry vertex load at command \(commandIndex)"
                        )
                    }
                    let count = Int(compact(tokens[1]))
                    let destination = Int(compact(tokens[2]))
                    guard count > 0, count <= 16, destination >= 0,
                          destination + count <= cache.count,
                          let sourceGroup = groups[groupHandle], sourceGroup.count >= count else {
                        throw GoldenEyeRarewareFrameV6.Error.sourceDrift(
                            "geometry vertex window at command \(commandIndex)"
                        )
                    }
                    for index in 0..<count {
                        cache[destination + index] = sourceGroup[index]
                    }
                }
                guard command.semantic.hasPrefix("gsSP1Triangle") else { continue }
                let tokens = Array(model.tokens(for: commandIndex))
                guard tokens.count == 4 else {
                    throw GoldenEyeRarewareFrameV6.Error.unsupportedVisibleCommand(
                        "Rareware triangle argument count at command \(commandIndex)"
                    )
                }
                let slots = tokens.prefix(3).map(compact)
                guard slots.allSatisfy({ $0 < UInt32(cache.count) }),
                      let source0 = cache[Int(slots[0])],
                      let source1 = cache[Int(slots[1])],
                      let source2 = cache[Int(slots[2])] else {
                    throw GoldenEyeRarewareFrameV6.Error.sourceDrift(
                        "geometry triangle cache at command \(commandIndex)"
                    )
                }
                let vertexStart = UInt32(vertices.count)
                for source in [source0, source1, source2] {
                    vertices.append(Vertex(
                        sourceIndex: source.id,
                        x: source.x,
                        y: source.y,
                        z: source.z,
                        s: source.s,
                        t: source.t,
                        nx: Int8(bitPattern: source.nx),
                        ny: Int8(bitPattern: source.ny),
                        nz: Int8(bitPattern: source.nz),
                        rgba: UInt32(source.r) << 24 | UInt32(source.g) << 16 |
                            UInt32(source.b) << 8 | UInt32(source.a)
                    ))
                }
                triangles.append(Triangle(
                    passIndex: UInt32(passIndex),
                    textureIndex: activeTextureIndex,
                    sourceCommandOffset: UInt32(commandIndex),
                    vertexStart: vertexStart
                ))
            }
        }

        guard triangles.count == Int(frame.sourceTriangleCount),
              vertices.count == triangles.count * 3 else {
            throw GoldenEyeRarewareFrameV6.Error.sourceDrift(
                "geometry output triangles=\(triangles.count) vertices=\(vertices.count)"
            )
        }
        for (index, triangle) in triangles.enumerated() {
            let expectedTexture = frame.passes[Int(triangle.passIndex)].textureIndices.last
            if triangle.passIndex == 1 {
                guard frame.passes[1].textureIndices.contains(triangle.textureIndex) else {
                    throw GoldenEyeRarewareFrameV6.Error.sourceDrift(
                        "LOD triangle texture \(triangle.textureIndex)"
                    )
                }
            } else {
                guard triangle.textureIndex == expectedTexture else {
                    throw GoldenEyeRarewareFrameV6.Error.sourceDrift(
                        "body triangle texture \(triangle.textureIndex)"
                    )
                }
            }
            guard triangle.vertexStart == UInt32(index * 3) else {
                throw GoldenEyeRarewareFrameV6.Error.sourceDrift("geometry vertex order")
            }
        }

        var geometryHash: UInt64 = 1_469_598_103_934_665_603
        for vertex in vertices {
            for value in [
                UInt64(vertex.sourceIndex),
                UInt64(UInt32(bitPattern: vertex.x)),
                UInt64(UInt32(bitPattern: vertex.y)),
                UInt64(UInt32(bitPattern: vertex.z)),
                UInt64(UInt32(bitPattern: vertex.s)),
                UInt64(UInt32(bitPattern: vertex.t)),
                UInt64(vertex.rgba),
            ] {
                geometryHash = hash(geometryHash, value)
            }
        }
        for triangle in triangles {
            geometryHash = hash(geometryHash, UInt64(triangle.passIndex))
            geometryHash = hash(geometryHash, UInt64(triangle.textureIndex))
            geometryHash = hash(geometryHash, UInt64(triangle.sourceCommandOffset))
        }
        return GoldenEyeRarewareGeometryV6(
            vertices: vertices,
            triangles: triangles,
            sourceCommandHash: frame.sourceCommandHash,
            geometryHash: geometryHash == 0 ? 1 : geometryHash
        )
    }

    private static func tokenValue(_ token: GoldenEyeSourceModelV6.Token) -> GoldenEyeSourceModelV6.TokenValue {
        if token.text == "null" { return .null }
        if token.text == "true" { return .boolean(true) }
        if token.text == "false" { return .boolean(false) }
        if let integer = Int64(token.text) { return .integer(integer) }
        if token.text.hasPrefix("0x"), let integer = Int64(token.text.dropFirst(2), radix: 16) {
            return .integer(integer)
        }
        if token.text.hasPrefix("handle("), token.text.count > 8 {
            let body = token.text.dropFirst(7).dropLast()
            let pieces = body.split(separator: ",")
            if pieces.count == 2, let value = UInt32(pieces[1].dropFirst(2), radix: 16) {
                return .handle(kind: .opaque, value: value)
            }
        }
        return .constant(name: token.text, value: token.encodedValue)
    }

    private static func compact(_ token: GoldenEyeSourceModelV6.Token) -> UInt32 {
        switch tokenValue(token) {
        case .integer(let value): return UInt32(truncatingIfNeeded: value)
        case .constant(_, let value): return value
        case .handle(_, let value): return value
        case .null: return GoldenEyeSourceModelV6.nullHandle
        case .boolean(let value): return value ? 1 : 0
        }
    }

    private static func hash(_ seed: UInt64, _ value: UInt64) -> UInt64 {
        var result = seed ^ value
        result &*= 1_099_511_628_211
        return result
    }
}

/// Capture requirements for the source-faithful Rareware lane.  The actual
/// Metal renderer consumes this immutable spec; keeping the paths validated
/// here prevents test-only captures from escaping into tracked source or from
/// being mistaken for the historical diagnostic screenshots.
struct GoldenEyeRarewareCaptureSpecV6: Sendable, Equatable {
    let reference320URL: URL
    let faithfulHDURL: URL
    let sourceCommandHash: UInt64
    let frameHash: UInt64

    init(frame: GoldenEyeRarewareFrameV6, root: URL) throws {
        let nativeRoot = root
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("native", isDirectory: true)
            .standardizedFileURL
        let candidateRoot = root.standardizedFileURL
        guard candidateRoot.path == nativeRoot.deletingLastPathComponent().deletingLastPathComponent().path else {
            throw GoldenEyeRarewareFrameV6.Error.invalidInput("capture root must be the checkout root")
        }
        let captureRoot = nativeRoot.appendingPathComponent("rareware-reference-capture-v6", isDirectory: true)
        self.reference320URL = captureRoot.appendingPathComponent("rareware-320x240.raw")
        self.faithfulHDURL = captureRoot.appendingPathComponent("rareware-faithful-hd.raw")
        self.sourceCommandHash = frame.sourceCommandHash
        self.frameHash = frame.frameHash
    }
}
