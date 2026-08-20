import Foundation

var state = GEOriginalFrontendStateV6()
let status = ge_original_frontend_v6_init(&state)
guard status == 0 else {
    fputs("ge_original_frontend_v6_swift_smoke: init failed\n", stderr)
    exit(1)
}
guard state.screen == 0, state.source_timer == 0 else {
    fputs("ge_original_frontend_v6_swift_smoke: state mismatch\n", stderr)
    exit(1)
}
print("ge_original_frontend_v6_swift_smoke: PASS")
