import Foundation

@main
struct GoldenEyeSourceFrontendFileModeIntegrationSmoke {
    static func main() {
        do {
            try run()
            print("goldeneye_source_frontend_file_mode_integration_smoke: PASS")
        } catch {
            fputs("goldeneye_source_frontend_file_mode_integration_smoke: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        var saved = GoldenEyeSaveState.blank
        let frozenWire = try GoldenEyeSaveCodec.encode(saved)
        precondition(frozenWire.count == GoldenEyeSaveCodec.fileByteCount)
        let semantic = try GoldenEyeFileModeAuthorityV6.semanticSnapshot(from: saved)
        precondition(MemoryLayout<GESaveSnapshotV1>.size == 432)
        let roundTrip = try GoldenEyeFileModeAuthorityV6.saveState(from: semantic)
        precondition(roundTrip == saved)
        try GoldenEyeSaveActions.createFolder(&saved, at: 2)
        saved.folders[2].setStageTimeByte(0, value: 1)
        let changedWire = try GoldenEyeSaveCodec.encode(saved)
        precondition(changedWire.count == 596)
        let changedSemantic = try GoldenEyeFileModeAuthorityV6.semanticSnapshot(from: saved)
        let changedRoundTrip = try GoldenEyeFileModeAuthorityV6.saveState(from: changedSemantic)
        precondition(changedRoundTrip == saved)

        var authority = try GoldenEyeSourceFrontendAuthorityV6()
        try authority.installSaveState(saved)
        var integrated: GoldenEyeSourceFrontendFrameV6?
        for tick in UInt64(1)...UInt64(4_500) {
            let sourceConfirm = tick >= 3_423
                ? UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_CONFIRM)
                : UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE)
            let frame = try authority.step(
                try GoldenEyeSourceFrontendTimelineV6(nativeTick: tick),
                buttonsPressed: sourceConfirm,
                controllerCount: 1,
                clockTimer: 1,
                focused: true,
                controllerConnected: true,
                synthetic: true,
                modelResultModel: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL),
                modelResultOperation: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK),
                modelResultFlags: UInt32(
                    GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_BLOOD_COMPLETE |
                        GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED
                )
            )
            if frame.fileModeFrame != nil {
                integrated = frame
                break
            }
        }
        guard let initialFrame = integrated, let initialMenu = initialFrame.fileModeFrame else {
            throw IntegrationError.sidecarNeverActivated
        }
        var frame = initialFrame
        var menu = initialMenu
        if menu.state.screen == GE_FILE_MODE_V6_SCREEN_MODE_SELECT.rawValue {
            frame = try authority.step(
                try GoldenEyeSourceFrontendTimelineV6(nativeTick: frame.nativeTick + 1),
                buttonsPressed: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_CANCEL),
                controllerCount: 1,
                clockTimer: 1,
                focused: true,
                controllerConnected: true,
                synthetic: true
            )
            guard let returnedMenu = frame.fileModeFrame else {
                throw IntegrationError.sidecarDropped
            }
            menu = returnedMenu
        }
        precondition(menu.state.screen == GE_FILE_MODE_V6_SCREEN_FILE_SELECT.rawValue)
        precondition(menu.walletSwitchMask == 0x0f)
        precondition(menu.textFlags & 1 != 0)

        let nextTick = frame.nativeTick + 1
        let selected = try authority.step(
            try GoldenEyeSourceFrontendTimelineV6(nativeTick: nextTick),
            buttonsPressed: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_CONFIRM),
            controllerCount: 1,
            clockTimer: 1,
            focused: true,
            controllerConnected: true,
            synthetic: true
        )
        guard let selectedMenu = selected.fileModeFrame else {
            throw IntegrationError.sidecarDropped
        }
        precondition(selectedMenu.state.screen == GE_FILE_MODE_V6_SCREEN_MODE_SELECT.rawValue)
        precondition(selectedMenu.walletSwitchMask == 1)
        precondition(selectedMenu.lastAction == GE_FILE_MODE_V6_SAVE_SELECT.rawValue)
        precondition(authority.fileModeSaveState?.selectedFolder == 0)

        let initialCursorX = selectedMenu.state.cursorXQ16
        let inputTick = selected.nativeTick + 1
        let keyboardMenu = try authority.step(
            try GoldenEyeSourceFrontendTimelineV6(nativeTick: inputTick),
            buttonsPressed: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE),
            controllerCount: 1,
            fileModeControllerCount: 0,
            clockTimer: 1,
            focused: true,
            controllerConnected: true,
            synthetic: true,
            fileModeHeld: UInt32(GE_FILE_MODE_V6_BUTTON_DPAD_RIGHT),
            fileModeStickX: 75,
            fileModeStickY: 0
        )
        guard let keyboardMenuFrame = keyboardMenu.fileModeFrame else {
            throw IntegrationError.sidecarDropped
        }
        precondition(keyboardMenuFrame.state.controllerCount == 0)
        precondition(keyboardMenuFrame.state.flags & GE_FILE_MODE_V6_STATE_FLAG_MULTI_AVAILABLE == 0)
        precondition(keyboardMenuFrame.state.cursorXQ16 != initialCursorX)

        let physicalMenu = try authority.step(
            try GoldenEyeSourceFrontendTimelineV6(nativeTick: inputTick + 1),
            buttonsPressed: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE),
            controllerCount: 2,
            fileModeControllerCount: 2,
            clockTimer: 1,
            focused: true,
            controllerConnected: true,
            synthetic: true,
            fileModeHeld: UInt32(GE_FILE_MODE_V6_BUTTON_DPAD_LEFT),
            fileModeStickX: -80,
            fileModeStickY: 0
        )
        guard let physicalMenuFrame = physicalMenu.fileModeFrame else {
            throw IntegrationError.sidecarDropped
        }
        precondition(physicalMenuFrame.state.controllerCount == 2)
        precondition(physicalMenuFrame.state.flags & GE_FILE_MODE_V6_STATE_FLAG_MULTI_AVAILABLE != 0)
    }

    private enum IntegrationError: Error {
        case sidecarNeverActivated
        case sidecarDropped
    }
}
