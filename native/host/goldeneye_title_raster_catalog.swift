import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Swift value-only view of the additive title-raster source vector.  The
/// catalog lets the title owner attach the source raster policy/hash to an
/// immutable frame without retaining any C pointers or raw Gfx words.  It
/// intentionally exposes deferred coverage/forced-blend flags rather than
/// inventing a Metal equivalent for unsupported source behavior.
struct GoldenEyeTitleRasterCatalog: Sendable, Equatable {
    enum ScreenID: Sendable {
        case legal, nintendo, rareware, gunbarrel, goldenEye, fileSelect, modeSelect, cast, ramrom
    }

    struct State: Sendable, Equatable {
        let sourceMask: UInt32
        let rawOtherModeH: UInt32
        let rawOtherModeL: UInt32
        let cycleType: UInt32
        let textureLOD: UInt32
        let alphaCompare: UInt32
        let depthSource: UInt32
        let zCompare: UInt32
        let zUpdate: UInt32
        let forceBlend: UInt32
        let loweringFlags: UInt32
        let stateHash: UInt64
    }

    let states: [State]
    let aggregateHash: UInt64

    enum Error: Swift.Error, CustomStringConvertible {
        case invalidStatus(UInt32)
        case invalidCount(UInt32)

        var description: String {
            switch self {
            case .invalidStatus(let status): return "title raster C status \(status)"
            case .invalidCount(let count): return "title raster C state count \(count)"
            }
        }
    }

    init() throws {
        let result = ge_title_lower_source_raster_v5()
        guard result.status == GE_STATUS_OK else {
            throw Error.invalidStatus(result.status)
        }
        guard result.state_count == GE_TITLE_RASTER_V5_STATE_CAPACITY else {
            throw Error.invalidCount(result.state_count)
        }
        let importedStates = [
            result.states.0, result.states.1, result.states.2, result.states.3,
            result.states.4, result.states.5, result.states.6, result.states.7,
        ]
        self.states = (0..<Int(result.state_count)).map { index in
            let state = importedStates[index]
            return State(
                sourceMask: state.source_model_mask,
                rawOtherModeH: state.raw_other_mode_h,
                rawOtherModeL: state.raw_other_mode_l,
                cycleType: state.cycle_type,
                textureLOD: state.texture_lod,
                alphaCompare: state.alpha_compare,
                depthSource: state.depth_source,
                zCompare: state.z_compare,
                zUpdate: state.z_update,
                forceBlend: state.force_blend,
                loweringFlags: state.lowering_flags,
                stateHash: state.state_hash
            )
        }
        self.aggregateHash = result.aggregate_hash
    }

    /// Source-group association used by title evidence. The returned state
    /// is a copied Swift value; coverage/forced-blend remains diagnostic.
    func state(for screen: ScreenID) -> State {
        let index: Int = switch screen {
        case .legal: 0
        case .nintendo: 1
        case .goldenEye: 3
        case .rareware: 7
        case .fileSelect, .modeSelect: 4
        case .gunbarrel, .cast, .ramrom: 0
        }
        return states[min(index, states.count - 1)]
    }
}
