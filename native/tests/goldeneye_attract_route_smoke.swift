import Foundation

@main
struct GoldenEyeAttractRouteSmoke {
    private static let sourceSeed: UInt64 = 0xAB8D_9F77_8128_0783

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("usage: goldeneye_attract_route_smoke /absolute/boot-asset-root")
        }
        let assetRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let catalog = try GoldenEyeRamRomRouteCatalog.parsed(assetRoot: assetRoot)
        precondition(catalog.isComplete)
        precondition(catalog.entries.count == 14)
        precondition(catalog.entries.map(\.demoID) == Array(1...14).map(UInt8.init))

        var route = GoldenEyeAttractRoute(catalog: catalog, randomSeed: sourceSeed)
        precondition(route.beginCast(.normalAttract) == 1)
        for expected in UInt16(2)...UInt16(8) {
            precondition(route.advanceCast() == .showCast(expected))
        }
        precondition(route.requestDemo(catalogIndex: 13))
        let routeAction = advanceToLaunch(route: &route)
        guard case let .launchDemo(request) = routeAction else {
            preconditionFailure("normal cast must end at a parsed RAMROM selection")
        }
        precondition(request.catalogIndex == 13)
        precondition(request.demoID == 14)
        precondition(request.stageID == 25)
        precondition(route.takeLaunchRequest() == request)
        precondition(route.takeLaunchRequest() == nil, "launch requests are one-shot")
        precondition(route.finishDemo(.completed))
        precondition(route.exitReason == .completed)

        for explicitIndex in UInt8(0)..<UInt8(14) {
            var explicitRoute = GoldenEyeAttractRoute(
                catalog: catalog,
                randomSeed: sourceSeed
            )
            _ = explicitRoute.beginCast(.normalAttract)
            precondition(explicitRoute.requestDemo(catalogIndex: explicitIndex))
            let action = advanceToLaunch(route: &explicitRoute, includeMainCast: true)
            guard case let .launchDemo(selected) = action else {
                preconditionFailure("explicit demo \(explicitIndex) was not selected")
            }
            precondition(selected.catalogIndex == explicitIndex)
            precondition(selected.demoID == explicitIndex + 1)
        }

        try checkBootFlow(catalog: catalog)
        print("goldeneye_attract_route_smoke: PASS cast=34 demos=14")
    }

    private static func advanceToLaunch(
        route: inout GoldenEyeAttractRoute,
        includeMainCast: Bool = false
    ) -> GoldenEyeAttractRouteAction {
        if includeMainCast {
            for expected in UInt16(2)...UInt16(8) {
                precondition(route.advanceCast() == .showCast(expected))
            }
        }
        for _ in 0..<8 {
            let action = route.advanceCast()
            if case .launchDemo = action { return action }
            if case .catalogUnavailable = action { return action }
        }
        preconditionFailure("cast route exceeded the four optional guests")
    }

    private static func checkBootFlow(catalog: GoldenEyeRamRomRouteCatalog) throws {
        var flow = GoldenEyeBootFlow(ramRomCatalog: catalog, randomSeed: sourceSeed)
        var snapshot = flow.step()
        for _ in 0..<489 { snapshot = flow.step() }
        precondition(snapshot.screen == .nintendo)

        let confirm = GoldenEyeTitleInput(pressed: 1 << 0)
        snapshot = flow.step(input: confirm)
        for _ in 0..<8 { snapshot = flow.step() }
        precondition(snapshot.screen == .rareware)
        snapshot = flow.step(input: confirm)
        for _ in 0..<8 { snapshot = flow.step() }
        precondition(snapshot.screen == .gunbarrel)
        snapshot = flow.step(input: confirm)
        for _ in 0..<8 { snapshot = flow.step() }
        precondition(snapshot.screen == .goldenEye)

        precondition(flow.requestRamRomDemo(catalogIndex: 13))
        var visitedCast: [UInt32] = []
        var previousCast: UInt32?
        for _ in 0..<6_000 {
            snapshot = flow.step()
            if snapshot.screen == .cast, previousCast != snapshot.subphase {
                visitedCast.append(snapshot.subphase)
                previousCast = snapshot.subphase
            }
            if snapshot.screen == .ramrom { break }
        }
        precondition(snapshot.screen == .ramrom)
        precondition(Array(visitedCast.prefix(8)) == Array(1...8).map(UInt32.init))
        precondition(snapshot.demoIndex == 13)

        let launch = flow.takeRamRomLaunchRequest()
        precondition(launch?.demoID == 14)
        precondition(launch?.stageID == 25)
        precondition(flow.takeRamRomLaunchRequest() == nil)

        // The source abort condition is any newly pressed controller button,
        // not just A/B/Start.  Use an unrelated bit to guard that behavior.
        snapshot = flow.step(input: GoldenEyeTitleInput(pressed: 1 << 10))
        for _ in 0..<8 { snapshot = flow.step() }
        precondition(snapshot.screen == .fileSelect)
    }
}
