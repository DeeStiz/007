import Foundation

@main
struct GoldenEyeCastTextureSetupV6Smoke {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/native/cast-frontend-v6-image-decoder-v6-fullweapons", isDirectory: true)
        let catalog = try GoldenEyeSourceFrontendCatalog.loadCast(preparedAssetRoot: root)
        let modelName = CommandLine.arguments.dropFirst().dropFirst().first ?? "natalya"
        let model = try GoldenEyeSourceModelV6.load(from: root.appendingPathComponent("\(modelName).gesm"))
        let compilation = GESourceModelCompilerV6.compile(model, modelName: modelName)
        guard let scene = compilation.scene, compilation.diagnostics.isEmpty else {
            fatalError("compile failed \(compilation.diagnostics)")
        }
        let commands = scene.commands.enumerated().map {
            GoldenEyeSourceTextureSetupCommandV6(sequence: UInt32($0.offset), compiled: $0.element)
        }
        let result = try GoldenEyeSourceTextureSetupResolverV6.resolve(
            modelName: modelName, model: model, catalog: catalog, commands: commands
        )
        guard !result.setups.isEmpty,
              result.setups.allSatisfy({ $0.modelName == modelName }),
              result.setups.allSatisfy({ !$0.levels.isEmpty }) else {
            fatalError("cast texture setup evidence is incomplete for \(modelName)")
        }
        let assets = try GoldenEyeSource2DAssetsV6(catalog: catalog)
        let lowerer = GoldenEyeSource2DLowererV6(assets: assets)
        func sourceHash(_ value: String) -> UInt32 {
            value.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        }
        let cast2D = try lowerer.makeCastFrame(
            nativeTick: 2,
            sourceTimer: 90,
            textSourceHashes: [sourceHash("STARRING"), sourceHash("007"), sourceHash("JAMESBOND")],
            fadeAlpha: 255,
            fullActorIntro: false
        )
        guard cast2D.screen == 7, cast2D.glyphs.isEmpty == false,
              cast2D.fills.isEmpty else {
            fatalError("cast source text/fade packet is incomplete")
        }
        let castSymbols = [
            "LF", "THEACTORS", "STARRING", "ALSOFEATURING", "GUESTSTAR", "007",
            "JAMESBOND", "NATALYASIMONOVA", "006", "ALECTREVELYAN", "JANUSOPPERATIVE",
            "XENIAONPTOPP", "GENERAL", "ARKADYOURUMOV", "BORISGRISHENKO", "EXKGBAGENT",
            "VELENTINZUKOVSKY", "DEFENSEMINISTER", "DIMITRIMISHKIN", "MAYDAY", "JAWS",
            "ODDJOB", "BERONSAMEDI", "JUNGLECOMMANDO", "STPETERSBURGGUARD", "RUSSIANINFANTRY",
            "RUSSIANSOLDIER", "JANUSMARINE", "JANUSSPECIALFORCES", "RUSSIANCOMMANDANT",
            "NAVALOFFICER", "SIBERIANGUARD", "ARCTICCOMMANDO", "SIBERIANSPECIALFORCES",
            "MOONRAKERELITE", "HELICOPTERPILOT", "SCIENTIST", "CIVILIAN"
        ]
        for symbol in castSymbols {
            let frame = try lowerer.makeCastFrame(
                nativeTick: 2, sourceTimer: 90,
                textSourceHashes: [sourceHash(symbol), sourceHash("LF"), sourceHash("LF")],
                fadeAlpha: 192, fullActorIntro: true
            )
            guard frame.fills.count == 1 else {
                fatalError("Cast text/fade row is incomplete for \(symbol)")
            }
        }
        print("goldeneye_cast_texture_setup_v6_smoke: PASS model=\(modelName) commands=\(commands.count) setups=\(result.setups.count) castGlyphs=\(cast2D.glyphs.count) castTextRows=\(castSymbols.count)")
    }
}
