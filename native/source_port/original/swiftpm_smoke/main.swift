import Foundation
import GoldenEyeOriginalFrontend
import GoldenEyeNative

var state = GEOriginalFrontendStateV6()
let status = ge_original_frontend_v6_init(&state)
guard status == 0 else {
    fputs("GoldenEyeOriginalFrontendSmoke: init failed\n", stderr)
    exit(1)
}
guard state.screen == 0, state.source_timer == 0 else {
    fputs("GoldenEyeOriginalFrontendSmoke: state mismatch\n", stderr)
    exit(1)
}
var nativeRequest = GEInitRequestV1()
nativeRequest.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
nativeRequest.header.struct_size = UInt32(MemoryLayout<GEInitRequestV1>.size)
nativeRequest.flags = 0
nativeRequest.reserved = 0
let nativeStatus = ge_native_initialize(nativeRequest)
guard nativeStatus == GE_STATUS_OK else {
    fputs("GoldenEyeOriginalFrontendSmoke: GoldenEyeNative init failed\n", stderr)
    exit(1)
}
_ = ge_native_shutdown()
var events = [GEOriginalFrontendEventV6](
    repeating: GEOriginalFrontendEventV6(), count: 16
)
var eventCount: UInt32 = 0
let captureStatus = events.withUnsafeMutableBufferPointer { buffer in
    ge_original_frontend_v6_capture_constructor(
        &state,
        1,
        1,
        buffer.baseAddress,
        UInt32(buffer.count),
        &eventCount
    )
}
guard captureStatus == 0, state.unsupported_count == 0, eventCount > 0 else {
    fputs("GoldenEyeOriginalFrontendSmoke: Nintendo capture mismatch\n", stderr)
    exit(1)
}

func sourceInput(for tick: UInt64) -> GEOriginalFrontendInputV6 {
    var input = GEOriginalFrontendInputV6()
    input.header.abi_version = 1
    input.header.struct_size = UInt32(MemoryLayout<GEOriginalFrontendInputV6>.size)
    input.record_version = 1
    input.flags = 6 /* connected + synthetic; deliberately no capture */
    input.controller_count = 1
    input.clock_timer = 1
    input.native_tick = tick
    input.sequence = tick
    return input
}

var noCaptureState = GEOriginalFrontendStateV6()
guard ge_original_frontend_v6_init(&noCaptureState) == 0 else {
    fputs("GoldenEyeOriginalFrontendSmoke: no-capture init failed\n", stderr)
    exit(1)
}
var sawNoCaptureGap = false
for tick in UInt64(1)...UInt64(750) {
    var input = sourceInput(for: tick)
    var frame = GEOriginalFrontendFrameV6()
    var noCaptureEvents = [GEOriginalFrontendEventV6](
        repeating: GEOriginalFrontendEventV6(), count: 32
    )
    var noCaptureCount: UInt32 = 0
    let stepStatus = noCaptureEvents.withUnsafeMutableBufferPointer { buffer in
        ge_original_frontend_v6_step(
            &noCaptureState,
            &input,
            buffer.baseAddress,
            UInt32(buffer.count),
            &noCaptureCount,
            &frame
        )
    }
    guard stepStatus == 0 else {
        fputs("GoldenEyeOriginalFrontendSmoke: no-capture step failed\n", stderr)
        exit(1)
    }
    for event in noCaptureEvents.prefix(Int(noCaptureCount)) {
        if event.kind == 5 { sawNoCaptureGap = true }
    }
}
guard noCaptureState.screen == 2, !sawNoCaptureGap,
      noCaptureState.unsupported_count == 0 else {
    fputs("GoldenEyeOriginalFrontendSmoke: no-capture authority mismatch\n", stderr)
    exit(1)
}
var rareBoundaryEvents = [GEOriginalFrontendEventV6](
    repeating: GEOriginalFrontendEventV6(), count: 16
)
var rareBoundaryCount: UInt32 = 0
let rareBoundaryStatus = rareBoundaryEvents.withUnsafeMutableBufferPointer { buffer in
    ge_original_frontend_v6_capture_constructor(
        &noCaptureState,
        2,
        751,
        buffer.baseAddress,
        UInt32(buffer.count),
        &rareBoundaryCount
    )
}
guard rareBoundaryStatus == 0, noCaptureState.unsupported_count == 0,
      rareBoundaryCount > 0 else {
    fputs("GoldenEyeOriginalFrontendSmoke: Rareware capture mismatch\n", stderr)
    exit(1)
}
print("GoldenEyeOriginalFrontendSmoke: PASS")
